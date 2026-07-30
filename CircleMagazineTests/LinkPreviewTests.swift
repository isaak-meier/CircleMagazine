//
//  LinkPreviewTests.swift
//  CircleMagazineTests
//
//  The link card's data layer: scraped metadata (or the absence of it) becoming
//  something a view can lay out without checking anything. The rule under test
//  throughout is that a link is always postable and always renders — a page that
//  publishes nothing still reads as its own domain.
//

import Foundation
import Testing
@testable import CircleMagazine

struct LinkPreviewTests {

    private let article = URL(string: "https://www.theatlantic.com/science/quiet")!

    private func meta(title: String? = nil, image: String? = nil,
                      site: String? = nil) -> OpenGraph.Meta {
        OpenGraph.Meta(title: title, imageURL: image.flatMap(URL.init(string:)), siteName: site)
    }

    // MARK: - The title fallback chain
    //
    // og:title → og:site_name → host. Each rung exists because the one below it
    // reads worse, and the bottom rung is never empty.

    @Test func aScrapedTitleIsUsedAsIs() {
        let preview = LinkPreview(destination: article, meta: meta(title: "The Quietest Place"))
        #expect(preview.title == "The Quietest Place")
    }

    /// A site that publishes only og:site_name still names itself better than
    /// its domain does.
    @Test func siteNameStandsInForAMissingTitle() {
        let preview = LinkPreview(destination: article, meta: meta(site: "The Atlantic"))
        #expect(preview.title == "The Atlantic")
    }

    @Test func theHostIsTheLastResort() {
        #expect(LinkPreview(destination: article, meta: meta()).title == "theatlantic.com")
    }

    /// A scrape that found nothing at all is an ordinary post, not a broken one.
    @Test func noMetadataAtAllStillPreviews() {
        let preview = LinkPreview(destination: article, meta: nil)
        #expect(preview.title == "theatlantic.com")
        #expect(preview.image == nil)
        #expect(preview.destination == article)
    }

    /// A stored empty string counts as absent — otherwise the card renders a
    /// blank line where the headline goes.
    @Test func anEmptyOrWhitespaceTitleFallsBackToTheHost() {
        #expect(LinkPreview(destination: article, title: "", image: nil).title == "theatlantic.com")
        #expect(LinkPreview(destination: article, title: "   ", image: nil).title == "theatlantic.com")
    }

    // MARK: - Host

    /// "www." is noise on a provenance line.
    @Test func theHostDropsWWW() {
        #expect(LinkPreview(destination: article, meta: nil).host == "theatlantic.com")
    }

    @Test func aHostWithoutWWWIsLeftAlone() {
        let url = URL(string: "https://news.ycombinator.com/item?id=1")!
        #expect(LinkPreview(destination: url, meta: nil).host == "news.ycombinator.com")
    }

    @Test func theHostIsLowercased() {
        let url = URL(string: "https://WWW.Example.COM/a")!
        #expect(LinkPreview(destination: url, meta: nil).host == "example.com")
    }

    // MARK: - Destination

    /// The card opens the link the member pasted, not the canonical URL the
    /// scraped page claims — they shared this one, tracking params and all.
    @Test func theDestinationIsTheLinkAsPasted() {
        let url = URL(string: "https://example.com/a?utm_source=circle")!
        #expect(LinkPreview(destination: url, meta: meta(title: "T")).destination == url)
    }

    // MARK: - Image

    /// Compose previews the freshly scraped image directly; nothing is stored yet.
    @Test func aScrapedImagePreviewsDirectly() {
        let preview = LinkPreview(destination: article,
                                  meta: meta(title: "T", image: "https://cdn.example.com/c.jpg"))
        #expect(preview.image == .direct(URL(string: "https://cdn.example.com/c.jpg")!))
    }

    // MARK: - Round trip through a stored page

    private func page(title: String?) -> Page {
        Page(id: UUID(), issueId: UUID(), submittedBy: nil, title: title, caption: nil,
             captionStyle: nil, cardShape: nil, createdAt: nil)
    }

    private func media(url: String?, poster: String? = nil, type: String? = "article") -> PageMedia {
        PageMedia(id: UUID(), pageId: nil, mediaUrl: url, mediaType: type, textContent: nil,
                  posterUrl: poster, posterFocus: nil, position: 0, createdAt: nil)
    }

    private func card(title: String?, url: String?, poster: String? = nil) -> CardViewModel {
        CardViewModel(from: MagazinePage(page: page(title: title),
                                         pageMedia: [media(url: url, poster: poster)],
                                         author: nil))
    }

    /// The stored shape: link in media_url, headline on the page, image as a
    /// bucket path the feed signs at render time.
    @Test func anArticleRowBecomesALinkCard() {
        let vm = card(title: "The Quietest Place",
                      url: "https://www.theatlantic.com/science/quiet",
                      poster: "circle-folder/cover.jpg")
        guard case .link(let preview)? = vm.media.first else {
            #expect(Bool(false), "an article row is a link card")
            return
        }
        #expect(preview.title == "The Quietest Place")
        #expect(preview.host == "theatlantic.com")
        #expect(preview.image == .stored(path: "circle-folder/cover.jpg"))
    }

    /// A stored link with no image is normal — most of the web has no og:image.
    @Test func anArticleRowWithoutAnImageIsStillACard() {
        let vm = card(title: "Headline", url: "https://example.com/a")
        guard case .link(let preview)? = vm.media.first else {
            #expect(Bool(false), "an article row is a link card")
            return
        }
        #expect(preview.image == nil)
    }

    /// Junk in media_url is a broken row, not a card that renders a blank host.
    @Test func anArticleRowWithAnUnparseableURLFallsBack() {
        guard case .fallback? = card(title: "T", url: "not a url").media.first else {
            #expect(Bool(false), "expected a fallback")
            return
        }
    }

    @Test func anArticleRowWithNoURLFallsBack() {
        guard case .fallback? = card(title: "T", url: nil).media.first else {
            #expect(Bool(false), "expected a fallback")
            return
        }
    }

    // MARK: - How the feed treats a link card

    @Test func aLinkCardIsGroupedAsALink() {
        #expect(card(title: "T", url: "https://example.com/a").medium == .link)
    }

    /// A headline and a thumbnail stretched to a full page would be mostly
    /// empty paper, so a link card sizes to itself like the video cards do.
    @Test func aLinkCardHugsItsMedia() {
        #expect(card(title: "T", url: "https://example.com/a").hugsItsMedia)
    }

    /// Links run after the players — the edition reads as sections.
    @Test func linksSortAfterVideoAndBeforeEverythingElse() {
        #expect(CardViewModel.Medium.allCases == [.youtube, .instagram, .link, .other])
    }

    // MARK: - Compose preview matches the feed

    /// The author approves a preview; the edition must show the same thing.
    /// Both routes build the same `LinkPreview`, and this pins that they agree.
    @Test func theComposePreviewMatchesTheStoredCard() {
        let scraped = meta(title: "The Quietest Place", image: "https://cdn.example.com/c.jpg")
        let preview = CardViewModel(previewingLink: article, meta: scraped, author: nil,
                                    caption: "worth it", captionStyle: .paperPlate)
        let stored = card(title: scraped.title, url: article.absoluteString,
                          poster: "circle-folder/cover.jpg")

        guard case .link(let previewed)? = preview.media.first,
              case .link(let rendered)? = stored.media.first else {
            #expect(Bool(false), "both routes make link cards")
            return
        }
        #expect(previewed.title == rendered.title)
        #expect(previewed.host == rendered.host)
        #expect(previewed.destination == rendered.destination)
        // The image is the one thing that differs by design: compose shows the
        // scraped URL, the feed a path it signs.
        #expect(previewed.image == .direct(URL(string: "https://cdn.example.com/c.jpg")!))
        #expect(rendered.image == .stored(path: "circle-folder/cover.jpg"))
    }

    /// The title the author saw is the title that gets written to the page.
    @Test func thePreviewCardCarriesTheTitleThatWillBeStored() {
        let vm = CardViewModel(previewingLink: article, meta: meta(site: "The Atlantic"),
                               author: nil, caption: nil, captionStyle: .paperPlate)
        #expect(vm.title == "The Atlantic")
    }

    @Test func aPreviewOfAnUnscrapableLinkIsNamedByItsHost() {
        let vm = CardViewModel(previewingLink: article, meta: nil, author: nil,
                               caption: nil, captionStyle: .paperPlate)
        #expect(vm.title == "theatlantic.com")
        #expect(vm.medium == .link)
    }
}
