//
//  IssueViewModelTests.swift
//  CircleMagazineTests
//
//  IssueViewModel's surface other than the phase itself: liveIssueId, the
//  appear/refresh commands, delete, and the compose VM it vends. Phase routing
//  (including the debug override) lives in EditionPhaseTests.
//
//  Serialized and clearing `forceComposePhase` up front — the override lives in
//  shared UserDefaults, so a value left by another suite would skew `state`.
//

import Foundation
import Testing
@testable import CircleMagazine

// MARK: - DB spy

private final class SpyDatabase: DatabaseService, @unchecked Sendable {
    struct Boom: Error, LocalizedError {
        var errorDescription: String? { "row level security" }
    }

    /// What fetchCurrentIssue returns. `.some(nil)` ⇒ nothing live (compose
    /// phase); nil ⇒ it throws.
    var stubbedMagazine: Magazine??
    var stubbedLiveIssueId: UUID?
    var deletePageError: Error?

    private(set) var fetchCalls: [UUID] = []
    private(set) var deletedPageIds: [UUID] = []

    override func fetchCurrentIssue(circleId: UUID) async throws -> Magazine? {
        fetchCalls.append(circleId)
        guard let stubbedMagazine else { throw Boom() }
        return stubbedMagazine
    }

    override func currentIssueId(circleId: UUID) async throws -> UUID? { stubbedLiveIssueId }

    override func deletePage(pageId: UUID) async throws {
        if let deletePageError { throw deletePageError }
        deletedPageIds.append(pageId)
    }
}

// MARK: - Suite

@Suite(.serialized) @MainActor
struct IssueViewModelTests {
    private let spy = SpyDatabase()
    private let circleId = UUID()
    private let me = User(id: UUID(), username: "You Person", bio: nil, avatarUrl: nil,
                          role: nil, followCredits: nil, circleSlots: nil,
                          isVerified: nil, createdAt: nil)

    init() {
        UserDefaults.standard.removeObject(forKey: IssueViewModel.forceComposeKey)
    }

    private func makeVM() -> IssueViewModel {
        IssueViewModel(store: IssueStore(db: spy), circleId: circleId, me: me)
    }

    /// A magazine with a known issue id, so liveIssueId is checkable.
    private func magazine(issueId: UUID = UUID()) -> Magazine {
        Magazine(issue: Issue(id: issueId, circleId: circleId, publishDate: "2026-07-25",
                              isLive: true, createdAt: nil),
                 pages: [])
    }

    private func phase(_ state: IssueLoadState) -> String {
        switch state {
        case .loading:      "loading"
        case .loaded:       "loaded"
        case .composing:    "composing"
        case .failedToLoad: "failed"
        }
    }

    private func failureText(_ state: IssueLoadState) -> String? {
        if case .failedToLoad(let error) = state { return error }
        return nil
    }

    // MARK: - Identity

    @Test func exposesTheCircleAndUserItWasBuiltFor() {
        let vm = makeVM()
        #expect(vm.circleId == circleId)
        #expect(vm.me.id == me.id)
    }

    // MARK: - liveIssueId

    @Test func liveIssueIdIsTheLoadedEditionsId() async {
        let issueId = UUID()
        spy.stubbedMagazine = .some(magazine(issueId: issueId))
        let vm = makeVM()
        await vm.refresh()
        #expect(vm.liveIssueId == issueId)
    }

    @Test func liveIssueIdIsNilBeforeAnythingLoads() {
        #expect(makeVM().liveIssueId == nil)
    }

    /// The compose phase has no live edition by definition.
    @Test func liveIssueIdIsNilInTheComposePhase() async {
        spy.stubbedMagazine = .some(nil)
        let vm = makeVM()
        await vm.refresh()
        #expect(phase(vm.state) == "composing")
        #expect(vm.liveIssueId == nil)
    }

    @Test func liveIssueIdIsNilAfterAFailedLoad() async {
        spy.stubbedMagazine = nil   // throws
        let vm = makeVM()
        await vm.refresh()
        #expect(vm.liveIssueId == nil)
    }

    // MARK: - refresh

    @Test func refreshLoadsALiveEdition() async {
        spy.stubbedMagazine = .some(magazine())
        let vm = makeVM()
        await vm.refresh()
        #expect(phase(vm.state) == "loaded")
    }

    /// Nothing live is the compose phase, not an error — the distinction the
    /// whole two-phase circle screen rests on.
    @Test func refreshWithNothingLiveIsComposingNotFailed() async {
        spy.stubbedMagazine = .some(nil)
        let vm = makeVM()
        await vm.refresh()
        #expect(phase(vm.state) == "composing")
    }

    @Test func refreshSurfacesTheErrorTextOnFailure() async {
        spy.stubbedMagazine = nil
        let vm = makeVM()
        await vm.refresh()
        #expect(phase(vm.state) == "failed")
        #expect(failureText(vm.state) == "row level security")
    }

    /// Unlike `appear`, refresh always refetches — it's the pull-to-refresh path.
    @Test func refreshAlwaysRefetches() async {
        spy.stubbedMagazine = .some(magazine())
        let vm = makeVM()
        await vm.refresh()
        await vm.refresh()
        #expect(spy.fetchCalls.count == 2)
    }

    @Test func refreshOnlyEverFetchesItsOwnCircle() async {
        spy.stubbedMagazine = .some(magazine())
        await makeVM().refresh()
        #expect(spy.fetchCalls == [circleId])
    }

    /// A recovered failure becomes a normal load — the state isn't sticky.
    @Test func refreshCanRecoverFromAFailure() async {
        spy.stubbedMagazine = nil
        let vm = makeVM()
        await vm.refresh()
        #expect(phase(vm.state) == "failed")
        spy.stubbedMagazine = .some(magazine())
        await vm.refresh()
        #expect(phase(vm.state) == "loaded")
    }

    // MARK: - appear

    @Test func appearDoesTheFirstLoad() async {
        spy.stubbedMagazine = .some(magazine())
        let vm = makeVM()
        await vm.appear()
        #expect(phase(vm.state) == "loaded")
        #expect(spy.fetchCalls.count == 1)
    }

    /// Re-entering a circle whose edition hasn't changed spends one cheap id
    /// check and no full fetch.
    @Test func appearSkipsTheRefetchWhenTheLiveEditionIsUnchanged() async {
        let issueId = UUID()
        spy.stubbedMagazine = .some(magazine(issueId: issueId))
        spy.stubbedLiveIssueId = issueId
        let vm = makeVM()
        await vm.appear()
        await vm.appear()
        #expect(spy.fetchCalls.count == 1)
    }

    /// A new edition going live is exactly when the second appear must refetch.
    @Test func appearRefetchesWhenANewEditionWentLive() async {
        let first = UUID()
        spy.stubbedMagazine = .some(magazine(issueId: first))
        spy.stubbedLiveIssueId = first
        let vm = makeVM()
        await vm.appear()

        let second = UUID()
        spy.stubbedMagazine = .some(magazine(issueId: second))
        spy.stubbedLiveIssueId = second
        await vm.appear()
        #expect(spy.fetchCalls.count == 2)
        #expect(vm.liveIssueId == second)
    }

    /// Nothing cached yet (compose phase) means appear keeps trying the full
    /// load, so the screen flips over as soon as the edition publishes.
    @Test func appearRetriesTheFullLoadWhileInTheComposePhase() async {
        spy.stubbedMagazine = .some(nil)
        let vm = makeVM()
        await vm.appear()
        await vm.appear()
        #expect(spy.fetchCalls.count == 2)
        #expect(phase(vm.state) == "composing")
    }

    @Test func appearRetriesAfterAFailure() async {
        spy.stubbedMagazine = nil
        let vm = makeVM()
        await vm.appear()
        spy.stubbedMagazine = .some(magazine())
        await vm.appear()
        #expect(phase(vm.state) == "loaded")
    }

    // MARK: - delete

    @Test func deleteRemovesThePageAndRefetches() async {
        spy.stubbedMagazine = .some(magazine())
        let vm = makeVM()
        let pageId = UUID()
        await vm.delete(pageId: pageId)
        #expect(spy.deletedPageIds == [pageId])
        #expect(spy.fetchCalls.count == 1)   // the refresh that follows the delete
    }

    /// A rejected delete (RLS: not your page) still refreshes, so the card the
    /// user tried to remove reappears rather than vanishing optimistically.
    @Test func deleteFailureStillRefreshes() async {
        spy.stubbedMagazine = .some(magazine())
        spy.deletePageError = SpyDatabase.Boom()
        let vm = makeVM()
        await vm.delete(pageId: UUID())
        #expect(spy.deletedPageIds.isEmpty)
        #expect(spy.fetchCalls.count == 1)
        #expect(phase(vm.state) == "loaded")
    }

    // MARK: - Child VMs

    @Test func composeVMIsVendedForTheSignedInAuthor() async {
        spy.stubbedMagazine = .some(magazine())
        let vm = makeVM()
        await vm.refresh()
        let compose = vm.composeVM()
        #expect(compose.author.id == me.id)
        #expect(!compose.canPost)   // nothing pasted yet
    }

    /// In the compose phase there's no issue id to seed, so the compose model
    /// falls back to asking the DB by circle — which is what opens the draft.
    @Test func composeVMIsStillVendedInTheComposePhase() async {
        spy.stubbedMagazine = .some(nil)
        let vm = makeVM()
        await vm.refresh()
        #expect(vm.liveIssueId == nil)
        #expect(vm.composeVM().author.id == me.id)
    }

    @Test func commentsVMIsBuiltForTheRequestedPage() {
        let vm = makeVM()
        let comments = vm.commentsVM(for: UUID())
        #expect(comments.me.id == me.id)
    }
}
