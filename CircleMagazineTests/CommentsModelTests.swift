//
//  CommentsModelTests.swift
//  CircleMagazineTests
//
//  CommentsModel's public surface: the load state machine, canSend's two
//  conditions, and send's optimistic append — including the failure branch that
//  deliberately keeps the draft so a retry doesn't lose what was typed.
//

import Foundation
import Testing
@testable import CircleMagazine

// MARK: - DB spy

private final class SpyDatabase: DatabaseService, @unchecked Sendable {
    struct Boom: Error, LocalizedError {
        var errorDescription: String? { "network is down" }
    }

    /// What fetchComments resolves to; nil ⇒ it throws.
    var stubbedComments: [CommentWithAuthor]?
    /// Set to make postComment throw instead of succeeding.
    var postError: Error?
    /// Runs while postComment is suspended — lets tests observe `posting`.
    var onPost: (@Sendable () async -> Void)?

    private(set) var fetchCalls: [UUID] = []
    private(set) var postCalls: [(pageId: UUID, userId: UUID, body: String)] = []

    override func fetchComments(pageId: UUID) async throws -> [CommentWithAuthor] {
        fetchCalls.append(pageId)
        guard let stubbedComments else { throw Boom() }
        return stubbedComments
    }

    // Fully qualified: Swift Testing exports its own `Comment`, so the bare
    // name is ambiguous under `@testable import CircleMagazine`.
    override func postComment(pageId: UUID, userId: UUID,
                              body: String) async throws -> CircleMagazine.Comment {
        await onPost?()
        postCalls.append((pageId, userId, body))
        if let postError { throw postError }
        return CircleMagazine.Comment(id: UUID(), pageId: pageId, userId: userId,
                                      body: body, createdAt: nil)
    }
}

// MARK: - Suite

@Suite(.serialized) @MainActor
struct CommentsModelTests {
    private let spy = SpyDatabase()
    private let pageId = UUID()
    private let me = User(id: UUID(), username: "You Person", bio: nil, avatarUrl: nil,
                          role: nil, followCredits: nil, circleSlots: nil,
                          isVerified: nil, createdAt: nil)

    private func makeModel() -> CommentsModel {
        CommentsModel(db: spy, pageId: pageId, me: me)
    }

    private func comment(_ body: String, by author: User? = nil) -> CommentWithAuthor {
        let user = author ?? me
        return CommentWithAuthor(
            comment: CircleMagazine.Comment(id: UUID(), pageId: pageId, userId: user.id,
                                            body: body, createdAt: nil),
            author: user)
    }

    /// Which case the state is in. `Issue` is one of the app's own model types,
    /// so Swift Testing's `Issue.record` is out of reach — labels read as well.
    private func label(_ state: CommentsModel.LoadState) -> String {
        switch state {
        case .loading: "loading"
        case .loaded:  "loaded"
        case .failed:  "failed"
        }
    }

    private func bodies(_ state: CommentsModel.LoadState) -> [String]? {
        guard case .loaded(let list) = state else { return nil }
        return list.map(\.comment.body)
    }

    private func failureMessage(_ state: CommentsModel.LoadState) -> String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    // MARK: - Initial state

    @Test func startsLoadingWithAnEmptyDraft() {
        let model = makeModel()
        #expect(label(model.state) == "loading")
        #expect(model.draft.isEmpty)
        #expect(!model.posting)
        #expect(!model.canSend)
        #expect(model.me.id == me.id)
    }

    // MARK: - load

    @Test func loadPublishesTheCommentsOldestFirst() async {
        spy.stubbedComments = [comment("first"), comment("second")]
        let model = makeModel()
        await model.load()
        #expect(bodies(model.state) == ["first", "second"])
    }

    @Test func loadOfAPageWithNoCommentsLoadsAnEmptyList() async {
        spy.stubbedComments = []
        let model = makeModel()
        await model.load()
        #expect(label(model.state) == "loaded")
        #expect(bodies(model.state) == [])
    }

    @Test func loadAsksAboutThisPageOnly() async {
        spy.stubbedComments = []
        await makeModel().load()
        #expect(spy.fetchCalls == [pageId])
    }

    @Test func loadFailureCarriesTheReason() async {
        spy.stubbedComments = nil   // throws
        let model = makeModel()
        await model.load()
        #expect(label(model.state) == "failed")
        #expect(failureMessage(model.state) == "network is down")
    }

    /// Unlike CirclesViewModel.load, this one has no idempotence guard — the
    /// sheet can pull again and a recovered network replaces the failure.
    @Test func loadCanRecoverFromAFailure() async {
        spy.stubbedComments = nil
        let model = makeModel()
        await model.load()
        #expect(label(model.state) == "failed")
        spy.stubbedComments = [comment("back online")]
        await model.load()
        #expect(bodies(model.state) == ["back online"])
    }

    @Test func loadReplacesRatherThanAppends() async {
        spy.stubbedComments = [comment("one")]
        let model = makeModel()
        await model.load()
        spy.stubbedComments = [comment("two")]
        await model.load()
        #expect(bodies(model.state) == ["two"])
    }

    // MARK: - canSend

    @Test func cannotSendAnEmptyDraft() {
        #expect(!makeModel().canSend)
    }

    @Test func cannotSendWhitespaceOnly() {
        let model = makeModel()
        model.draft = "   \n\t "
        #expect(!model.canSend)
    }

    @Test func canSendOnceThereIsRealText() {
        let model = makeModel()
        model.draft = "nice one"
        #expect(model.canSend)
    }

    /// The second condition: no double-sending while a post is in flight.
    @Test func cannotSendWhileAPostIsInFlight() async {
        spy.stubbedComments = []
        let model = makeModel()
        await model.load()
        model.draft = "hold on"

        nonisolated(unsafe) var midPostCanSend: Bool?
        nonisolated(unsafe) var midPostPosting: Bool?
        spy.onPost = {
            midPostCanSend = await MainActor.run { model.canSend }
            midPostPosting = await MainActor.run { model.posting }
        }
        await model.send()
        #expect(midPostPosting == true)
        #expect(midPostCanSend == false)
        #expect(!model.posting)   // cleared by the defer once the write returns
    }

    // MARK: - send

    @Test func sendPassesThePageAuthorAndTrimmedBody() async {
        spy.stubbedComments = []
        let model = makeModel()
        await model.load()
        model.draft = "  well said  "
        await model.send()
        let call = try! #require(spy.postCalls.first)
        #expect(call.pageId == pageId)
        #expect(call.userId == me.id)
        #expect(call.body == "well said")
    }

    @Test func sendAppendsTheCommentAndClearsTheDraft() async {
        spy.stubbedComments = [comment("existing")]
        let model = makeModel()
        await model.load()
        model.draft = "mine"
        await model.send()
        #expect(bodies(model.state) == ["existing", "mine"])
        #expect(model.draft.isEmpty)
        #expect(!model.canSend)
    }

    @Test func theAppendedCommentCarriesMeAsItsAuthor() async {
        spy.stubbedComments = []
        let model = makeModel()
        await model.load()
        model.draft = "mine"
        await model.send()
        guard case .loaded(let list) = model.state else { return }
        #expect(list.first?.author?.id == me.id)
    }

    /// Sending before the load lands still works — the model starts a fresh
    /// list rather than dropping the comment on the floor.
    @Test func sendWhileStillLoadingStartsTheListWithThatComment() async {
        let model = makeModel()
        model.draft = "eager"
        await model.send()
        #expect(bodies(model.state) == ["eager"])
    }

    @Test func sendingAnEmptyDraftDoesNothing() async {
        spy.stubbedComments = []
        let model = makeModel()
        await model.load()
        await model.send()
        #expect(spy.postCalls.isEmpty)
        #expect(bodies(model.state) == [])
    }

    @Test func sendingWhitespaceOnlyDoesNothingAndKeepsIt() async {
        spy.stubbedComments = []
        let model = makeModel()
        await model.load()
        model.draft = "   "
        await model.send()
        #expect(spy.postCalls.isEmpty)
        #expect(model.draft == "   ")
    }

    // MARK: - send failures

    /// The deliberate behaviour: a failed post keeps the draft so the user can
    /// retry, and doesn't wipe comments already on screen with an error state.
    @Test func postFailureKeepsTheDraftAndTheLoadedComments() async {
        spy.stubbedComments = [comment("existing")]
        let model = makeModel()
        await model.load()
        model.draft = "will fail"
        spy.postError = SpyDatabase.Boom()
        await model.send()
        #expect(model.draft == "will fail")
        #expect(bodies(model.state) == ["existing"])   // untouched, no error state
        #expect(!model.posting)
    }

    /// With nothing on screen to protect, the failure surfaces instead.
    @Test func postFailureWithNothingLoadedShowsTheError() async {
        spy.stubbedComments = nil
        let model = makeModel()
        await model.load()          // → .failed
        model.draft = "will fail"
        spy.postError = SpyDatabase.Boom()
        await model.send()
        #expect(label(model.state) == "failed")
        #expect(model.draft == "will fail")
    }

    @Test func retryAfterAFailedPostSucceeds() async {
        spy.stubbedComments = []
        let model = makeModel()
        await model.load()
        model.draft = "retry me"
        spy.postError = SpyDatabase.Boom()
        await model.send()
        #expect(bodies(model.state) == [])

        spy.postError = nil
        await model.send()          // draft survived, so no retyping
        #expect(bodies(model.state) == ["retry me"])
        #expect(model.draft.isEmpty)
    }
}
