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
        let circleId: UUID
        let authorId: UUID
        let videoURL: URL
        let caption: String?
        let captionStyle: CaptionStyle
        let cardShape: CardShape
    }

    /// A photo submission — the bytes and the framing that went to storage.
    struct PhotoCall {
        let issueId: UUID
        let circleId: UUID
        let authorId: UUID
        let jpeg: Data
        let caption: String?
        let cardShape: CardShape
    }

    struct NoEdition: Error {}

    var postCalls: [PostCall] = []
    var photoCalls: [PhotoCall] = []
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

    override func createVideoPost(issueId: UUID, circleId: UUID, authorId: UUID, videoURL: URL,
                                  caption: String?, captionStyle: CaptionStyle, cardShape: CardShape,
                                  insta: InstagramEmbed.Meta? = nil, posterFocus: Double? = nil) async throws -> Page {
        await onPost?()
        if let errorToThrow { throw errorToThrow }
        postCalls.append(PostCall(issueId: issueId, circleId: circleId, authorId: authorId,
                                  videoURL: videoURL, caption: caption,
                                  captionStyle: captionStyle, cardShape: cardShape))
        return Page(id: UUID(), issueId: issueId, submittedBy: authorId,
                    title: nil, caption: caption, captionStyle: captionStyle, createdAt: nil)
    }

    override func createPhotoPost(issueId: UUID, circleId: UUID, authorId: UUID, jpeg: Data,
                                  caption: String?, captionStyle: CaptionStyle,
                                  cardShape: CardShape) async throws -> Page {
        await onPost?()
        if let errorToThrow { throw errorToThrow }
        photoCalls.append(PhotoCall(issueId: issueId, circleId: circleId, authorId: authorId,
                                    jpeg: jpeg, caption: caption, cardShape: cardShape))
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
    /// Shown when the text isn't a URL at all. Any *link* is postable now, so
    /// this is only reached by things that don't parse as one.
    private let parseError = "That doesn't look like a link."
    /// A link that parses but that we won't fetch over cleartext.
    private let schemeError = "Links need to start with https."

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        YouTubeOEmbed.session = session
        InstagramEmbed.session = session   // insta resolve now scrapes the embed page
        StubURLProtocol.stubFor = nil
        StubURLProtocol.requested = false
    }

    /// The model no longer takes an edition — `post()` always asks the DB which
    /// one a submission belongs in, so the spy's answer IS the target.
    private func makeModel() -> ComposeModel {
        spy.stubbedSubmissionIssueId = issueId
        return ComposeModel(db: spy, circleId: circleId, author: author)
    }

    /// A model whose circle has no edition available and can't open one — the
    /// case where `issueIdForSubmission` throws.
    private func makeModelWithNoEdition() -> ComposeModel {
        spy.stubbedSubmissionIssueId = nil
        return ComposeModel(db: spy, circleId: circleId, author: author)
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

    /// Bare prose parses as a relative URL with no scheme, so it lands on the
    /// https guard rather than the parse one. Either way: not staged.
    @Test func plainTextShowsError() async {
        let model = makeModel()
        model.linkText = "check out this video"
        await resolveAndWait(model)
        #expect(model.errorText == schemeError)
        #expect(model.draft == nil)
    }

    /// The reader's device fetches whatever was pasted, so cleartext is refused
    /// before any request goes out.
    @Test func anHttpLinkIsRefused() async {
        let model = makeModel()
        model.linkText = "http://example.com/article"
        await resolveAndWait(model)
        #expect(model.errorText == schemeError)
        #expect(model.draft == nil)
    }

    // MARK: resolve — plain links
    //
    // Anything that isn't a YouTube or Instagram embed is a web link. It stages
    // whether or not the site published metadata, because a site's failure to
    // fill in its meta tags isn't a reason a member can't share it.

    @Test func aPlainLinkStagesAsAWebLink() async {
        stubOEmbed()   // not HTML, so the scrape finds nothing — the point here
        let model = makeModel()
        model.linkText = "https://example.com/article"
        await resolveAndWait(model)
        #expect(model.errorText == nil)
        #expect(model.webLink?.url.absoluteString == "https://example.com/article")
        #expect(model.canPost)
        #expect(!model.isResolving)
    }

    /// A link with no readable metadata is a normal post, not an error.
    @Test func aLinkWithoutMetadataStillStages() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = "https://example.com/article"
        await resolveAndWait(model)
        #expect(model.webLink?.meta == nil)
        #expect(model.canPost)
    }

    @Test func aPlainLinkIsNotAVideoDraft() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = "https://example.com/clip.mp4"
        await resolveAndWait(model)
        #expect(model.resolved == nil)      // not a player
        #expect(model.photo == nil)
        #expect(model.webLink != nil)
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
        let model = makeModel()
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
        let model = makeModelWithNoEdition()   // the DB can't open an edition
        model.linkText = watchLink
        await resolveAndWait(model)
        await model.post()
        #expect(model.errorText == "Couldn't open this week's edition — try again in a moment.")
        #expect(model.phase == .editing)
        #expect(spy.postCalls.isEmpty)
    }

    /// The model never names the edition itself — it asks the DB, which answers
    /// with the circle's open draft (opening one if this is the week's first
    /// submission). The screen's loaded edition never enters into it.
    @Test func postWritesIntoTheEditionTheDBNames() async {
        stubOEmbed()
        let fetched = UUID()
        let model = makeModel()
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
    /// The lookup is deliberately NOT cached across posts. The open draft rolls
    /// over at the week boundary, so a compose sheet left open across it must
    /// pick up the new edition rather than writing into the one that just
    /// published. Each post asks again and uses the current answer.
    @Test func postRepeatsTheEditionLookupOnRetry() async {
        stubOEmbed()
        let firstAnswer = UUID(), rolledOver = UUID()
        let model = makeModel()
        spy.stubbedSubmissionIssueId = firstAnswer
        model.linkText = watchLink
        await resolveAndWait(model)
        spy.errorToThrow = NSError(domain: "test", code: 1)
        await model.post()                          // lookup happens, write fails
        spy.errorToThrow = nil
        spy.stubbedSubmissionIssueId = rolledOver   // the week turned over
        await model.post()
        #expect(spy.postCalls.first?.issueId == rolledOver)
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

    // MARK: Photos
    //
    // A photo is the other half of `draft`, so these pin the parts a link can't
    // reach: that the bytes and the circle survive to the write, and that the
    // two kinds of draft genuinely replace each other rather than stacking.

    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])   // JPEG magic, enough to be distinct
    private var previewURL: URL { URL(string: "file:///tmp/compose-preview.jpg")! }

    @Test func stagingAPhotoMakesItPostable() {
        let model = makeModel()
        #expect(!model.canPost)
        model.stagePhoto(jpeg: jpeg, previewURL: previewURL)
        #expect(model.canPost)
        #expect(model.photo?.jpeg == jpeg)
        #expect(model.resolved == nil)   // it's a photo, not a link
    }

    /// The upload needs the circle: it's the storage folder, and the folder is
    /// what the bucket policy checks.
    @Test func postingAPhotoSendsTheBytesAndTheCircle() async {
        let model = makeModel()
        model.stagePhoto(jpeg: jpeg, previewURL: previewURL, shape: .tall)
        model.caption = "cousin got married"
        await model.post()

        #expect(model.phase == .posted)
        #expect(spy.postCalls.isEmpty)          // not a video post
        #expect(spy.photoCalls.count == 1)
        let call = spy.photoCalls[0]
        #expect(call.jpeg == jpeg)
        #expect(call.circleId == circleId)
        #expect(call.issueId == issueId)
        #expect(call.authorId == author.id)
        #expect(call.caption == "cousin got married")
        #expect(call.cardShape == .tall)
    }

    @Test func aPhotoWithNoCaptionSendsNilNotEmptyString() async {
        let model = makeModel()
        model.stagePhoto(jpeg: jpeg, previewURL: previewURL)
        await model.post()
        #expect(spy.photoCalls[0].caption == nil)
    }

    /// Picking a photo after pasting a link swaps the draft. Without this the
    /// two could both be staged and post() would silently pick one.
    @Test func stagingAPhotoReplacesAResolvedLink() async {
        stubOEmbed()
        let model = makeModel()
        model.linkText = watchLink
        await resolveAndWait(model)
        #expect(model.resolved != nil)

        model.stagePhoto(jpeg: jpeg, previewURL: previewURL)
        #expect(model.resolved == nil)
        #expect(model.photo != nil)
        #expect(model.linkText.isEmpty)

        await model.post()
        #expect(spy.photoCalls.count == 1)
        #expect(spy.postCalls.isEmpty)
    }

    /// …and the other direction: resolving a link over a staged photo leaves
    /// only the link.
    @Test func resolvingALinkReplacesAStagedPhoto() async {
        stubOEmbed()
        let model = makeModel()
        model.stagePhoto(jpeg: jpeg, previewURL: previewURL)
        model.linkText = watchLink
        await resolveAndWait(model)

        #expect(model.photo == nil)
        #expect(model.resolved != nil)

        await model.post()
        #expect(spy.postCalls.count == 1)
        #expect(spy.photoCalls.isEmpty)
    }

    @Test func photoShapeIsChangeableBeforePosting() async {
        let model = makeModel()
        model.stagePhoto(jpeg: jpeg, previewURL: previewURL, shape: .tall)
        model.setPhotoShape(.wide)
        #expect(model.photo?.shape == .wide)
        await model.post()
        #expect(spy.photoCalls[0].cardShape == .wide)
    }

    /// Changing the shape with nothing staged must not conjure a draft — Post
    /// would light up with nothing behind it.
    @Test func settingAShapeWithNothingStagedIsANoOp() {
        let model = makeModel()
        model.setPhotoShape(.wide)
        #expect(model.draft == nil)
        #expect(!model.canPost)
    }

    @Test func aFailedPhotoUploadRestoresEditing() async {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "storage is down" } }
        let model = makeModel()
        spy.errorToThrow = Boom()
        model.stagePhoto(jpeg: jpeg, previewURL: previewURL)
        await model.post()
        #expect(model.phase == .editing)
        #expect(model.errorText == "Couldn't post — storage is down")
        #expect(model.canPost)   // still staged, so they can retry
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
