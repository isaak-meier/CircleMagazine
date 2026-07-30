//
//  OpenGraphTests.swift
//  CircleMagazineTests
//
//  The link-preview scraper: what it reads out of real-world markup, what it
//  refuses, and what it does when a page gives it nothing. Parsing is pure, so
//  most of this needs no network; the fetch cases stub OpenGraph.session.
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
        var error: URLError?
    }

    nonisolated(unsafe) static var stubFor: (@Sendable (URL) -> Stub)?
    nonisolated(unsafe) static var requested = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.requested = true
        let stub = Self.stubFor?(request.url!) ?? Stub(status: 500)
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
}

@Suite(.serialized)
struct OpenGraphTests {

    private let base = URL(string: "https://example.com/article")!

    // MARK: - Parsing

    @Test func readsTheStandardOpenGraphTrio() {
        let meta = OpenGraph.parse("""
        <html><head>
        <meta property="og:title" content="The Quietest Place in America">
        <meta property="og:image" content="https://cdn.example.com/cover.jpg">
        <meta property="og:site_name" content="Example">
        </head></html>
        """, relativeTo: base)

        #expect(meta?.title == "The Quietest Place in America")
        #expect(meta?.imageURL?.absoluteString == "https://cdn.example.com/cover.jpg")
        #expect(meta?.siteName == "Example")
    }

    /// Attribute order isn't fixed in the wild — plenty of CMSes emit `content`
    /// first, and a parser that assumes otherwise silently reads nothing.
    @Test func readsTagsWithTheAttributesReversed() {
        let meta = OpenGraph.parse(
            #"<meta content="Backwards" property="og:title">"#, relativeTo: base)
        #expect(meta?.title == "Backwards")
    }

    @Test func readsSingleQuotedAttributes() {
        let meta = OpenGraph.parse("<meta property='og:title' content='Single'>", relativeTo: base)
        #expect(meta?.title == "Single")
    }

    /// Twitter's tags key off `name`, not `property`, and a lot of sites ship
    /// only those.
    @Test func fallsBackToTwitterCardTags() {
        let meta = OpenGraph.parse("""
        <meta name="twitter:title" content="Tweeted">
        <meta name="twitter:image" content="https://cdn.example.com/t.png">
        """, relativeTo: base)
        #expect(meta?.title == "Tweeted")
        #expect(meta?.imageURL?.absoluteString == "https://cdn.example.com/t.png")
    }

    @Test func openGraphWinsOverTwitterWhenBothArePresent() {
        let meta = OpenGraph.parse("""
        <meta name="twitter:title" content="Second choice">
        <meta property="og:title" content="First choice">
        """, relativeTo: base)
        #expect(meta?.title == "First choice")
    }

    /// A page with no cards at all still has a name.
    @Test func fallsBackToTheTitleTag() {
        let meta = OpenGraph.parse("<html><head><title>Just A Page</title></head></html>",
                                   relativeTo: base)
        #expect(meta?.title == "Just A Page")
        #expect(meta?.imageURL == nil)
    }

    @Test func aRelativeImageResolvesAgainstThePage() {
        let meta = OpenGraph.parse(#"<meta property="og:image" content="/img/cover.jpg">"#,
                                   relativeTo: base)
        #expect(meta?.imageURL?.absoluteString == "https://example.com/img/cover.jpg")
    }

    /// Entity-escaped ampersands are the norm in query-string image URLs; left
    /// encoded, the CDN gets a URL it doesn't recognise.
    @Test func decodesEntitiesInTitlesAndImageURLs() {
        let meta = OpenGraph.parse("""
        <meta property="og:title" content="Rock &amp; Roll">
        <meta property="og:image" content="https://cdn.example.com/c.jpg?w=1&amp;h=2">
        """, relativeTo: base)
        #expect(meta?.title == "Rock & Roll")
        #expect(meta?.imageURL?.absoluteString == "https://cdn.example.com/c.jpg?w=1&h=2")
    }

    /// Nothing usable is one answer — nil — rather than a Meta of three nils
    /// that every caller would have to unpick.
    @Test func aPageWithNoMetadataIsNil() {
        #expect(OpenGraph.parse("<html><body><p>hi</p></body></html>", relativeTo: base) == nil)
    }

    @Test func emptyContentIsIgnoredRatherThanReadAsATitle() {
        #expect(OpenGraph.parse(#"<meta property="og:title" content="">"#, relativeTo: base) == nil)
    }

    /// Duplicate tags: the first wins, so a later stray doesn't overwrite the
    /// one the page led with.
    @Test func theFirstOfADuplicatedTagWins() {
        let meta = OpenGraph.parse("""
        <meta property="og:title" content="Real">
        <meta property="og:title" content="Stray">
        """, relativeTo: base)
        #expect(meta?.title == "Real")
    }

    /// Unrelated metas (viewport, charset, description) must not be mistaken
    /// for preview data.
    @Test func ignoresMetaTagsThatArentPreviewData() {
        let meta = OpenGraph.parse("""
        <meta name="viewport" content="width=device-width">
        <meta name="description" content="Not a title">
        """, relativeTo: base)
        #expect(meta == nil)
    }

    // MARK: - Fetching

    private func stub(_ body: String, status: Int = 200, error: URLError? = nil) {
        StubURLProtocol.requested = false
        StubURLProtocol.stubFor = { _ in
            .init(status: status, body: Data(body.utf8), error: error)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        OpenGraph.session = URLSession(configuration: config)
    }

    private func restore() {
        OpenGraph.session = .shared
        StubURLProtocol.stubFor = nil
    }

    @Test func fetchReadsMetadataFromTheResponse() async {
        stub(#"<meta property="og:title" content="Fetched">"#)
        defer { restore() }
        let meta = await OpenGraph.fetch(URL(string: "https://example.com/a")!)
        #expect(meta?.title == "Fetched")
    }

    /// The request goes to a host we know nothing about, chosen by whoever
    /// pasted the link — it shouldn't also travel in the clear.
    @Test func httpIsRefusedWithoutSoMuchAsARequest() async {
        stub(#"<meta property="og:title" content="Should never load">"#)
        defer { restore() }
        let meta = await OpenGraph.fetch(URL(string: "http://example.com/a")!)
        #expect(meta == nil)
        #expect(!StubURLProtocol.requested)
    }

    @Test func aNon200IsNoPreviewRatherThanAnError() async {
        stub("<title>Nope</title>", status: 404)
        defer { restore() }
        #expect(await OpenGraph.fetch(URL(string: "https://example.com/a")!) == nil)
    }

    @Test func aNetworkFailureIsNoPreviewRatherThanAnError() async {
        stub("", error: URLError(.notConnectedToInternet))
        defer { restore() }
        #expect(await OpenGraph.fetch(URL(string: "https://example.com/a")!) == nil)
    }

    /// A page that publishes nothing readable is still a fine thing to post —
    /// the caller falls back to the bare link.
    @Test func aPageWithoutMetadataFetchesToNil() async {
        stub("<html><body>nothing here</body></html>")
        defer { restore() }
        #expect(await OpenGraph.fetch(URL(string: "https://example.com/a")!) == nil)
    }

    /// The read stops at the cap, so a hostile or merely enormous page can't
    /// pull unbounded bytes into memory. The head still parses.
    @Test func stopsReadingAfterTheCap() async {
        let head = #"<head><meta property="og:title" content="Capped"></head>"#
        stub(head + String(repeating: "<p>padding</p>", count: 200_000))
        defer { restore() }
        let meta = await OpenGraph.fetch(URL(string: "https://example.com/a")!)
        #expect(meta?.title == "Capped")
    }
}
