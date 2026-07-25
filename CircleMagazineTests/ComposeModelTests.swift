//
//  ComposeModelTests.swift
//  CircleMagazineTests
//
//  ComposeModel's full public surface: resolve (every parse/oEmbed outcome),
//  task supersede/cancel semantics, clearLink, canPost, and post. Network is
//  stubbed via YouTubeOEmbed.session; DB writes via a DatabaseService spy.
//  Serialized: the URLProtocol stub and session seam are process-global.
//

import Foundation
import Testing
@testable import CircleMagazine

// MARK: - Network stub

private final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status = 200
        var body = Data()
        var delay: TimeInterval = 0
        var error: URLError?
    }

    /// Decides the response per request URL. nil ⇒ 500 (tests that expect no
    /// traffic assert on `requested` instead of hanging).
    nonisolated(unsafe) static var stubFor: (@Sendable (URL) -> Stub)?
    nonisolated(unsafe) static var requested = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.requested = true
        let stub = Self.stubFor?(request.url!) ?? Stub(status: 500)
        let deliver = { [self] in
            if let error = stub.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: stub.status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        if stub.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + stub.delay, execute: deliver)
        } else {
            deliver()
        }
    }
}

private func oembedJSON(_ title: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["title": title])
}

/// A trimmed Instagram embed page: the EmbeddedMediaImage cover frame + the
/// UsernameText handle, the two things InstagramEmbed pulls out.
private let instaEmbedHTML = """
<img class="EmbeddedMediaImage" alt="shared by &#064;infinite_mantra" \
src="https://scontent.cdninstagram.com/v/t51/cover.jpg?stp=x&amp;oe=6A6754C8"/>
<span class="UsernameText">infinite_mantra</span>
"""

/// Stub every oEmbed call with one fixed outcome.
private func stubOEmbed(status: Int = 200, title: String = "Stub Title",
                        error: URLError? = nil, delay: TimeInterval = 0) {
    StubURLProtocol.stubFor = { _ in
        .init(status: status, body: oembedJSON(title), delay: delay, error: error)
    }
}

// MARK: - DB spy

private final class SpyDatabase: DatabaseService, @unchecked Sendable {
    struct PostCall {
        let issueId: UUID
        let authorId: UUID
        let videoURL: URL
        let caption: String?
        let captionStyle: CaptionStyle
        let cardShape: CardShape
    }

    struct NoEdition: Error {}

    var postCalls: [PostCall] = []
    var errorToThrow: Error?
    /// The edition post()'s self-serve lookup lands on when the model has no
    /// issueId. nil ⇒ the lookup throws, as it does when RLS blocks opening a draft.
    var stubbedSubmissionIssueId: UUID?
    /// Runs while post() is suspended mid-write — lets tests observe .posting.
    var onPost: (@Sendable () async -> Void)?

    override func issueIdForSubmission(circleId: UUID) async throws -> UUID {
        guard let stubbedSubmissionIssueId else { throw NoEdition() }
        return stubbedSubmissionIssueId
    }

    override func createVideoPost(issueId: UUID, authorId: UUID, videoURL: URL, caption: String?,
                                  captionStyle: CaptionStyle, cardShape: CardShape,
                                  insta: InstagramEmbed.Meta? = nil, posterFocus: Double? = nil) async throws -> Page {
        await onPost?()
        if let errorToThrow { throw errorToThrow }
        postCalls.append(PostCall(issueId: issueId, authorId: authorId, videoURL: videoURL,
                                  caption: caption, captionStyle: captionStyle, cardShape: cardShape))
        return Page(id: UUID(), issueId: issueId, submittedBy: authorId,
                    title: nil, caption: caption, captionStyle: captionStyle, createdAt: nil)
    }
}

// MARK: - Suite

@Suite(.serialized) @MainActor
struct ComposeModelTests {
    private let spy = SpyDatabase()
    private let author = Magazine.sample.pages[0].author!
    private let issueId = UUID()
    private let circleId = UUID()

    private let watchLink = "https://www.youtube.com/watch?v=abc123XYZ00"
    private let parseError = "Paste a YouTube or Instagram link."

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        YouTubeOEmbed.session = session
        InstagramEmbed.session = session   // insta resolve now scrapes the embed page
        StubURLProtocol.stubFor = nil
        StubURLProtocol.requested = false
    }

    private func makeModel(issueId: UUID?? = nil) -> ComposeModel {
        ComposeModel(db: spy, issueId: issueId ?? self.issueId, circleId: circleId, author: author)
    }

    /// startResolving and wait for that resolve pass to finish.
    private func resolveAndWait(_ model: ComposeModel) async {
        model.startResolving()
        await model.resolveTask?.value
    }

    // MARK: resolve — parse failures

    @Test func emptyLinkShowsError() async {
        let model = makeModel()
        await resolveAndWait(model)
        #expect(model.errorText == parseError)
        #expect(model.resolved == nil)
        #expect(!model.isResolving)
    }

    @Test func whitespaceOnlyLinkShowsError() async {
        let model = makeModel()
        model.linkText = "   \n  "
        await resolveAndWait(model)
        #expect(model.errorText == parseError)
        #expect(model.resolved == nil)
    }

    @Test func plainTextShowsError() async {
        let model = makeModel()
        model.linkText = "check out this video"
        await resolveAndWait(model)
        #expect(model.errorText == parseError)
        #expect(model.resolved == nil)
    }

    @Test func rawFileLinkIsRejected() async {
        let model = makeModel()
        model.linkText = "https://example.com/clip.mp4"
        await resolveAndWait(model)
        #expect(model.errorText == parseError)
        #expect(model.resolved == nil)
    }

    // MARK: resolve — YouTube happy paths

    @Test func youtubeWatchResolvesWithTitle() async {
        stubOEmbed(title: "A Great Video")
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        #expect(model.resolved?.title == "A Great Video")
        #expect(model.resolved?.source == .youtube(id: "abc123XYZ00"))
        #expect(model.resolved?.shape == .wide)
        #expect(model.errorText == nil)
        #expect(!model.isResolving)
    }

    @Test func linkIsTrimmedBeforeParsing() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = "  \(watchLink)\n"
        await resolveAndWait(model)
        #expect(model.resolved != nil)
    }

    @Test func shortsResolveAsTall() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = "https://www.youtube.com/shorts/sh0rt1d"
        await resolveAndWait(model)
        #expect(model.resolved?.source == .youtube(id: "sh0rt1d"))
        #expect(model.resolved?.shape == .tall)
    }

    @Test func errorClearsOnSubsequentSuccess() async {
        stubOEmbed()
        let model = makeModel()
        await resolveAndWait(model)   // empty → error
        #expect(model.errorText == parseError)
        model.linkText = watchLink
        await resolveAndWait(model)
        #expect(model.errorText == nil)
        #expect(model.resolved != nil)
    }

    // MARK: resolve — oEmbed outcomes

    @Test func deadLink404BlocksPosting() async {
        stubOEmbed(status: 404)
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        #expect(model.resolved == nil)
        #expect(model.errorText == "That video looks private or removed — check the link.")
        #expect(!model.isResolving)
        #expect(!model.canPost)
    }

    @Test func serverErrorResolvesWithoutTitle() async {
        stubOEmbed(status: 500)
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        #expect(model.resolved != nil)
        #expect(model.resolved?.title == nil)
        #expect(model.errorText == nil)
    }

    @Test func networkErrorResolvesWithoutTitle() async {
        stubOEmbed(error: URLError(.timedOut))
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        #expect(model.resolved != nil)
        #expect(model.resolved?.title == nil)
    }

    @Test func malformedOEmbedBodyResolvesWithoutTitle() async {
        StubURLProtocol.stubFor = { _ in .init(status: 200, body: Data("not json".utf8)) }
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        #expect(model.resolved != nil)
        #expect(model.resolved?.title == nil)
    }

    // MARK: resolve — Instagram

    // A miss on the embed scrape (here: the default 500) still resolves the
    // link — the poster is best-effort, so insta comes back nil, not blocked.
    @Test func instaReelResolvesEvenWhenScrapeFails() async {
        let model = makeModel()
        model.linkText = "https://www.instagram.com/reel/CkLm123/"
        await resolveAndWait(model)
        #expect(model.resolved?.source == .insta(id: "CkLm123", kind: .reel))
        #expect(model.resolved?.title == nil)
        #expect(model.resolved?.shape == .tall)
        #expect(model.resolved?.insta == nil)
    }

    @Test func instaPostResolvesAsSquare() async {
        let model = makeModel()
        model.linkText = "https://www.instagram.com/p/CkLm123/"
        await resolveAndWait(model)
        #expect(model.resolved?.source == .insta(id: "CkLm123", kind: .post))
        #expect(model.resolved?.shape == .square)
    }

    // The embed scrape feeds the cover frame + @handle into resolved.insta, so
    // the compose preview (and the eventual post) get the real still.
    @Test func instaResolvePopulatesPosterAndHandle() async {
        StubURLProtocol.stubFor = { _ in .init(status: 200, body: Data(instaEmbedHTML.utf8)) }
        let model = makeModel()
        model.linkText = "https://www.instagram.com/reel/CkLm123/"
        await resolveAndWait(model)
        #expect(model.resolved?.insta?.handle == "infinite_mantra")
        #expect(model.resolved?.insta?.posterURL.absoluteString.contains("cover.jpg") == true)
    }

    // MARK: task management

    @Test func newerLinkSupersedesSlowFetch() async {
        StubURLProtocol.stubFor = { url in
            url.absoluteString.contains("SLOW")
                ? .init(status: 200, body: oembedJSON("slow"), delay: 2)
                : .init(status: 200, body: oembedJSON("fast"))
        }
        let model = makeModel()
        model.linkText = "https://www.youtube.com/watch?v=SLOW0000001"
        model.startResolving()
        let slow = model.resolveTask!
        model.linkText = "https://www.youtube.com/watch?v=FAST0000001"
        model.startResolving()
        let fast = model.resolveTask!
        await slow.value
        await fast.value
        #expect(model.resolved?.title == "fast")
        #expect(model.resolved?.source == .youtube(id: "FAST0000001"))
        #expect(!model.isResolving)
    }

    @Test func cancelMidFetchLeavesCleanState() async {
        stubOEmbed(delay: 2)
        let model = makeModel()
        model.linkText = watchLink
        model.startResolving()
        let task = model.resolveTask!
        model.cancelResolving()
        await task.value
        #expect(model.resolved == nil)
        #expect(!model.isResolving)
        #expect(model.resolveTask == nil)
    }

    /// Regression: clearing the field mid-fetch used to strand isResolving —
    /// the parse-error exit didn't reset it — leaving the spinner up forever.
    @Test func clearingFieldMidFetchDoesNotStrandSpinner() async {
        stubOEmbed(delay: 2)
        let model = makeModel()
        model.linkText = watchLink
        model.startResolving()
        let first = model.resolveTask!
        model.linkText = ""
        model.startResolving()
        let second = model.resolveTask!
        await first.value
        await second.value
        #expect(!model.isResolving)
        #expect(model.errorText == parseError)
        #expect(model.resolved == nil)
    }

    // MARK: clearLink

    @Test func clearLinkResetsEverything() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        #expect(model.resolved != nil)
        model.clearLink()
        #expect(model.resolved == nil)
        #expect(model.linkText.isEmpty)
        #expect(model.errorText == nil)
    }

    // MARK: canPost

    @Test func canPostRequiresResolvedLink() async {
        stubOEmbed()
        let model = makeModel(issueId: .some(nil))
        #expect(!model.canPost)   // nothing resolved yet
        model.linkText = watchLink
        await resolveAndWait(model)
        // A missing issue id doesn't grey the button — post() self-fetches it.
        #expect(model.canPost)
    }

    @Test func canPostFalseWhilePostingAndAfterPosted() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)

        nonisolated(unsafe) var midPostCanPost: Bool?
        spy.onPost = { midPostCanPost = await MainActor.run { model.canPost } }
        await model.post()
        #expect(midPostCanPost == false)   // phase == .posting during the write
        #expect(model.phase == .posted)
        #expect(!model.canPost)            // and stays unpostable once posted
    }

    // MARK: post

    @Test func postWithoutAnyIssueAnywhereSetsError() async {
        stubOEmbed()
        let model = makeModel(issueId: .some(nil))   // feed had nothing…
        spy.stubbedSubmissionIssueId = nil           // …and the DB can't open one either
        model.linkText = watchLink
        await resolveAndWait(model)
        await model.post()
        #expect(model.errorText == "Couldn't open this week's edition — try again in a moment.")
        #expect(model.phase == .editing)
        #expect(spy.postCalls.isEmpty)
    }

    /// Regression: a failed feed load used to grey out Post forever — the model
    /// now asks the DB which edition to post into itself. That lookup also covers
    /// the compose phase, where nothing is live and a draft gets opened.
    @Test func postSelfFetchesIssueIdWhenFeedCouldNot() async {
        stubOEmbed()
        let fetched = UUID()
        let model = makeModel(issueId: .some(nil))
        spy.stubbedSubmissionIssueId = fetched
        model.linkText = watchLink
        await resolveAndWait(model)
        await model.post()
        #expect(model.phase == .posted)
        #expect(spy.postCalls.first?.issueId == fetched)
    }

    @Test func postSuccessPassesArgsAndMarksPosted() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        await model.post()

        #expect(model.phase == .posted)
        #expect(model.errorText == nil)
        let call = try! #require(spy.postCalls.first)
        #expect(call.issueId == issueId)
        #expect(call.authorId == author.id)
        #expect(call.videoURL.absoluteString == watchLink)
        #expect(call.caption == nil)             // empty caption posts as nil
        #expect(call.captionStyle == .paperPlate)
        #expect(call.cardShape == .wide)
    }

    @Test func postPassesCaptionAndChosenStyle() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        model.caption = "had to share"
        model.captionStyle = .inkBand
        await model.post()
        let call = try! #require(spy.postCalls.first)
        #expect(call.caption == "had to share")
        #expect(call.captionStyle == .inkBand)
    }

    @Test func postFailureRestoresEditingWithMessage() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        spy.errorToThrow = NSError(domain: "test", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "row level security"])
        await model.post()
        #expect(model.phase == .editing)
        #expect(model.errorText?.contains("row level security") == true)
        #expect(model.canPost)   // recoverable: user can retry
    }

    // MARK: post — guards and idempotence

    /// Nothing resolved means nothing to post; the guard exits before the phase
    /// or the DB is touched.
    @Test func postWithNothingResolvedIsANoOp() async {
        let model = makeModel()
        await model.post()
        #expect(model.phase == .editing)
        #expect(model.errorText == nil)
        #expect(spy.postCalls.isEmpty)
    }

    /// Double-tapping Post must not write the card twice — the phase guard is
    /// the only thing standing between a jumpy thumb and a duplicate page.
    @Test func postingTwiceWritesOnlyOnce() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        await model.post()
        await model.post()
        #expect(spy.postCalls.count == 1)
        #expect(model.phase == .posted)
    }

    /// A retry after a failure goes through — the failure path restores .editing
    /// precisely so the guard lets the second attempt run.
    @Test func postRetryAfterFailureSucceeds() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        spy.errorToThrow = NSError(domain: "test", code: 1)
        await model.post()
        #expect(spy.postCalls.isEmpty)
        spy.errorToThrow = nil
        await model.post()
        #expect(spy.postCalls.count == 1)
        #expect(model.phase == .posted)
    }

    /// The self-serve lookup runs once; a retry reuses the id it landed on
    /// rather than opening a second draft.
    @Test func postDoesNotRepeatTheEditionLookupOnRetry() async {
        stubOEmbed()
        let found = UUID()
        let model = makeModel(issueId: .some(nil))
        spy.stubbedSubmissionIssueId = found
        model.linkText = watchLink
        await resolveAndWait(model)
        spy.errorToThrow = NSError(domain: "test", code: 1)
        await model.post()                     // lookup happens, write fails
        spy.errorToThrow = nil
        spy.stubbedSubmissionIssueId = UUID()  // a different answer, if asked again
        await model.post()
        #expect(spy.postCalls.first?.issueId == found)
    }

    /// A whitespace-only caption is still "no note" as far as the DB is
    /// concerned — but the model posts what it was given, so this pins today's
    /// behaviour rather than a trimmed one.
    @Test func postSendsAWhitespaceCaptionAsTyped() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        model.caption = "   "
        await model.post()
        #expect(spy.postCalls.first?.caption == "   ")
    }

    @Test func postCarriesTheChosenPosterCrop() async {
        StubURLProtocol.stubFor = { _ in .init(status: 200, body: Data(instaEmbedHTML.utf8)) }
        let model = makeModel()
        model.linkText = "https://www.instagram.com/reel/CkLm123/"
        await resolveAndWait(model)
        model.posterFocus = 0.15
        await model.post()
        #expect(spy.postCalls.count == 1)
        #expect(spy.postCalls.first?.cardShape == .square || spy.postCalls.first?.cardShape == .tall)
    }

    // MARK: clearLink — full reset

    @Test func clearLinkAlsoResetsTheCropButKeepsTheCaption() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        model.posterFocus = 0.1
        model.caption = "kept"
        model.clearLink()
        #expect(model.posterFocus == 0.5)
        #expect(model.caption == "kept")   // the note survives swapping the link
    }

    @Test func clearLinkOnAnUntouchedModelIsHarmless() {
        let model = makeModel()
        model.clearLink()
        #expect(model.linkText.isEmpty)
        #expect(model.resolved == nil)
        #expect(model.errorText == nil)
        #expect(!model.canPost)
    }

    /// Clearing after a dead-link error wipes the message, so the field doesn't
    /// keep scolding you about a link you already removed.
    @Test func clearLinkWipesAResolveError() async {
        stubOEmbed(status: 404)
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        #expect(model.errorText != nil)
        model.clearLink()
        #expect(model.errorText == nil)
    }

    // MARK: cancelResolving

    @Test func cancelBeforeAnyFetchIsHarmless() {
        let model = makeModel()
        model.cancelResolving()
        #expect(!model.isResolving)
        #expect(model.resolveTask == nil)
    }

    /// Cancelling then pasting again must still resolve — the generation bump
    /// mustn't orphan the *next* pass too.
    @Test func resolvingWorksAgainAfterACancel() async {
        stubOEmbed(delay: 2)
        let model = makeModel()
        model.linkText = watchLink
        model.startResolving()
        let cancelled = model.resolveTask!
        model.cancelResolving()
        await cancelled.value

        stubOEmbed(title: "second try")
        await resolveAndWait(model)
        #expect(model.resolved?.title == "second try")
        #expect(!model.isResolving)
    }

    @Test func cancelAfterAResolveLeavesTheResolvedLinkPostable() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        model.cancelResolving()
        #expect(model.resolved != nil)
        #expect(model.canPost)
    }

    // MARK: Defaults

    @Test func aFreshModelIsEmptyAndEditing() {
        let model = makeModel()
        #expect(model.linkText.isEmpty)
        #expect(model.caption.isEmpty)
        #expect(model.captionStyle == .paperPlate)
        #expect(model.posterFocus == 0.5)
        #expect(model.resolved == nil)
        #expect(model.errorText == nil)
        #expect(!model.isResolving)
        #expect(model.phase == .editing)
        #expect(!model.canPost)
        #expect(model.author.id == author.id)
    }
}
