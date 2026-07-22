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

    var postCalls: [PostCall] = []
    var errorToThrow: Error?
    /// What post()'s self-serve issue lookup finds when the model has no issueId.
    var stubbedCurrentIssueId: UUID?
    /// Runs while post() is suspended mid-write — lets tests observe .posting.
    var onPost: (@Sendable () async -> Void)?

    override func currentIssueId(live: Bool) async throws -> UUID? { stubbedCurrentIssueId }

    override func createVideoPost(issueId: UUID, authorId: UUID, videoURL: URL, caption: String?,
                                  captionStyle: CaptionStyle, cardShape: CardShape) async throws -> Page {
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

    private let watchLink = "https://www.youtube.com/watch?v=abc123XYZ00"
    private let parseError = "Paste a YouTube or Instagram link."

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        YouTubeOEmbed.session = URLSession(configuration: config)
        StubURLProtocol.stubFor = nil
        StubURLProtocol.requested = false
    }

    private func makeModel(issueId: UUID?? = nil) -> ComposeModel {
        ComposeModel(db: spy, issueId: issueId ?? self.issueId, author: author)
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

    // MARK: resolve — Instagram (no lookup)

    @Test func instaReelResolvesInstantlyWithoutNetwork() async {
        let model = makeModel()
        model.linkText = "https://www.instagram.com/reel/CkLm123/"
        await resolveAndWait(model)
        #expect(model.resolved?.source == .insta(id: "CkLm123", kind: .reel))
        #expect(model.resolved?.title == nil)
        #expect(model.resolved?.shape == .tall)
        #expect(!StubURLProtocol.requested)
    }

    @Test func instaPostResolvesAsSquare() async {
        let model = makeModel()
        model.linkText = "https://www.instagram.com/p/CkLm123/"
        await resolveAndWait(model)
        #expect(model.resolved?.source == .insta(id: "CkLm123", kind: .post))
        #expect(model.resolved?.shape == .square)
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
        spy.stubbedCurrentIssueId = nil              // …and neither does the DB
        model.linkText = watchLink
        await resolveAndWait(model)
        await model.post()
        #expect(model.errorText == "No live edition to post to yet — try again in a moment.")
        #expect(model.phase == .editing)
        #expect(spy.postCalls.isEmpty)
    }

    /// Regression: a failed feed load used to grey out Post forever — the model
    /// now asks the DB for the live edition itself.
    @Test func postSelfFetchesIssueIdWhenFeedCouldNot() async {
        stubOEmbed()
        let fetched = UUID()
        let model = makeModel(issueId: .some(nil))
        spy.stubbedCurrentIssueId = fetched
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
}
