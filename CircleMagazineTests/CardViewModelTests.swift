//
//  CardViewModelTests.swift
//  CircleMagazineTests
//
//  CardViewModel / CardMediaViewModel: the transform from raw DB rows (Page +
//  PageMedia) into something a card view renders without further thought.
//  Covers every mediaType branch, both nil-column defaults, ordering, and the
//  compose-preview initialiser. Shape-from-URL parsing lives in CardShapeTests.
//

import Foundation
import Testing
@testable import CircleMagazine

struct CardViewModelTests {

    // MARK: Fixtures

    private let youtubeURL = "https://www.youtube.com/watch?v=abc123XYZ00"
    private let instaReelURL = "https://www.instagram.com/reel/CkLm123/"

    private static func user(_ name: String) -> User {
        User(id: UUID(), username: name, bio: nil, avatarUrl: nil, role: nil,
             followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    }

    private let author = Self.user("Philly Bum Bum")

    private func page(title: String? = nil, caption: String? = nil,
                      captionStyle: CaptionStyle? = nil,
                      cardShape: CardShape? = nil) -> Page {
        Page(id: UUID(), issueId: UUID(), submittedBy: nil, title: title, caption: caption,
             captionStyle: captionStyle, cardShape: cardShape, createdAt: nil)
    }

    private func media(type: String?, url: String?, position: Int?,
                       poster: String? = nil, handle: String? = nil,
                       focus: Double? = nil) -> PageMedia {
        PageMedia(id: UUID(), pageId: nil, mediaUrl: url, mediaType: type,
                  textContent: handle, posterUrl: poster, posterFocus: focus,
                  position: position, createdAt: nil)
    }

    private func card(_ page: Page, _ media: [PageMedia], author: User? = nil) -> CardViewModel {
        CardViewModel(from: MagazinePage(page: page, pageMedia: media,
                                         author: author ?? self.author))
    }

    /// A one-line label for a media case, so failures read plainly.
    private func label(_ media: CardMediaViewModel) -> String {
        switch media {
        case .image:    "image"
        case .video:    "video"
        case .fallback: "fallback"
        }
    }

    // MARK: - Page fields

    @Test func carriesThePagesIdAuthorAndText() {
        let p = page(title: "Off-Grid", caption: "so dope")
        let vm = card(p, [])
        #expect(vm.id == p.id)
        #expect(vm.author?.username == "Philly Bum Bum")
        #expect(vm.title == "Off-Grid")
        #expect(vm.caption == "so dope")
    }

    @Test func titleAndCaptionStayNilWhenTheAuthorLeftThemOut() {
        let vm = card(page(), [])
        #expect(vm.title == nil)
        #expect(vm.caption == nil)
    }

    /// Pages predating the author join (or an anonymous row) still render.
    @Test func authorIsNilWhenThePageHasNoneAttached() {
        let vm = CardViewModel(from: MagazinePage(page: page(), pageMedia: [], author: nil))
        #expect(vm.author == nil)
    }

    // MARK: - Column defaults

    @Test func captionStyleDefaultsToPaperPlateWhenTheColumnIsNull() {
        #expect(card(page(captionStyle: nil), []).captionStyle == .paperPlate)
    }

    @Test func captionStyleIsUsedWhenTheColumnIsSet() {
        #expect(card(page(captionStyle: .inkBand), []).captionStyle == .inkBand)
    }

    @Test func cardShapeDefaultsToTallWhenTheColumnIsNull() {
        #expect(card(page(cardShape: nil), []).cardShape == .tall)
    }

    @Test func cardShapeIsUsedWhenTheColumnIsSet() {
        #expect(card(page(cardShape: .wide), []).cardShape == .wide)
    }

    // MARK: - Media ordering

    @Test func mediaIsEmptyForAPageWithNoRows() {
        #expect(card(page(), []).media.isEmpty)
    }

    @Test func mediaIsSortedByPosition() {
        let vm = card(page(), [
            media(type: "image", url: "https://example.com/c.jpg", position: 2),
            media(type: "image", url: "https://example.com/a.jpg", position: 0),
            media(type: "image", url: "https://example.com/b.jpg", position: 1),
        ])
        let urls = vm.media.map { media -> String in
            if case .image(let url) = media { return url.lastPathComponent }
            return "?"
        }
        #expect(urls == ["a.jpg", "b.jpg", "c.jpg"])
    }

    /// A null position sorts as 0, so legacy rows land first rather than crashing
    /// the sort or dropping out.
    @Test func nullPositionSortsAsZero() {
        let vm = card(page(), [
            media(type: "image", url: "https://example.com/second.jpg", position: 1),
            media(type: "image", url: "https://example.com/first.jpg", position: nil),
        ])
        if case .image(let url) = vm.media.first {
            #expect(url.lastPathComponent == "first.jpg")
        } else {
            #expect(Bool(false), "expected the null-position row first")
        }
    }

    @Test func everyMediaRowBecomesExactlyOneRenderableItem() {
        let vm = card(page(), [
            media(type: "image", url: "https://example.com/a.jpg", position: 0),
            media(type: "video", url: youtubeURL, position: 1),
            media(type: "text", url: nil, position: 2),
        ])
        #expect(vm.media.count == 3)
        #expect(vm.media.map(label) == ["image", "video", "fallback"])
    }

    // MARK: - Media mapping: images

    @Test func anImageRowBecomesAnImage() {
        let vm = card(page(), [media(type: "image", url: "https://example.com/a.jpg", position: 0)])
        if case .image(let url) = vm.media[0] {
            #expect(url.absoluteString == "https://example.com/a.jpg")
        } else {
            #expect(Bool(false), "expected .image, got \(label(vm.media[0]))")
        }
    }

    // MARK: - Media mapping: video

    @Test func aYouTubeRowBecomesAVideoWithNoPosterOrHandle() {
        let vm = card(page(), [media(type: "video", url: youtubeURL, position: 0)])
        guard case .video(let source, let poster, let handle, let focus) = vm.media[0] else {
            #expect(Bool(false), "expected .video, got \(label(vm.media[0]))")
            return
        }
        #expect(source == .youtube(id: "abc123XYZ00"))
        #expect(poster == nil)
        #expect(handle == nil)
        #expect(focus == 0.5)   // centered by default
    }

    @Test func anInstaRowCarriesItsStoredPosterHandleAndFocus() {
        let vm = card(page(), [media(type: "video", url: instaReelURL, position: 0,
                                     poster: "posters/CkLm123.jpg",
                                     handle: "infinite_mantra", focus: 0.2)])
        guard case .video(let source, let poster, let handle, let focus) = vm.media[0] else {
            #expect(Bool(false), "expected .video, got \(label(vm.media[0]))")
            return
        }
        #expect(source == .insta(id: "CkLm123", kind: .reel))
        #expect(handle == "infinite_mantra")
        #expect(focus == 0.2)
        guard case .stored(let path)? = poster else {
            #expect(Bool(false), "a feed poster must be a storage path needing signing")
            return
        }
        #expect(path == "posters/CkLm123.jpg")
    }

    /// A null crop means the author never dragged the preview — center it.
    @Test func nullPosterFocusCentersTheCrop() {
        let vm = card(page(), [media(type: "video", url: instaReelURL, position: 0, focus: nil)])
        guard case .video(_, _, _, let focus) = vm.media[0] else { return }
        #expect(focus == 0.5)
    }

    // MARK: - Media mapping: fallbacks

    /// Anything that isn't YouTube or Instagram parses as a directly-playable
    /// file, so a Vimeo row still renders as a video rather than falling back.
    /// (Compose refuses these up front; the feed will happily show one that's
    /// already in the DB.)
    @Test func anUnrecognisedHostBecomesARawFileVideo() {
        let vm = card(page(), [media(type: "video", url: "https://vimeo.com/12345", position: 0)])
        guard case .video(let source, _, _, _) = vm.media[0] else {
            #expect(Bool(false), "expected .video, got \(label(vm.media[0]))")
            return
        }
        guard case .rawFile(let url) = source else {
            #expect(Bool(false), "expected .rawFile for an unrecognised host")
            return
        }
        #expect(url.absoluteString == "https://vimeo.com/12345")
    }

    /// The genuine unparseable case: a YouTube watch link with no `?v=` id.
    /// VideoSource rejects it, so the card shows the error placeholder.
    @Test func aMalformedYouTubeLinkFallsBackWithAnError() {
        let vm = card(page(), [media(type: "video", url: "https://www.youtube.com/watch",
                                     position: 0)])
        guard case .fallback(let error) = vm.media[0] else {
            #expect(Bool(false), "expected .fallback, got \(label(vm.media[0]))")
            return
        }
        #expect(error?.errorDescription == "The url could not be parsed")
    }

    /// A bare instagram.com link names no post, so it can't resolve to content.
    @Test func anInstagramLinkWithNoPostIdFallsBack() {
        let vm = card(page(), [media(type: "video", url: "https://www.instagram.com/someone",
                                     position: 0)])
        #expect(label(vm.media[0]) == "fallback")
    }

    @Test func aRowWithNoURLAtAllFallsBackWithAnError() {
        let vm = card(page(), [media(type: "image", url: nil, position: 0)])
        guard case .fallback(let error) = vm.media[0] else {
            #expect(Bool(false), "expected .fallback, got \(label(vm.media[0]))")
            return
        }
        #expect(error != nil)
    }

    /// A parked media type (text, audio) is not an error — it just has nothing
    /// to draw yet, so it falls back silently.
    @Test func aParkedMediaTypeFallsBackWithoutAnError() {
        let vm = card(page(), [media(type: "text", url: "https://example.com/x", position: 0)])
        guard case .fallback(let error) = vm.media[0] else {
            #expect(Bool(false), "expected .fallback, got \(label(vm.media[0]))")
            return
        }
        #expect(error == nil)
    }

    @Test func aNullMediaTypeFallsBackWithoutAnError() {
        let vm = card(page(), [media(type: nil, url: "https://example.com/x", position: 0)])
        guard case .fallback(let error) = vm.media[0] else {
            #expect(Bool(false), "expected .fallback, got \(label(vm.media[0]))")
            return
        }
        #expect(error == nil)
    }

    // MARK: - isTallInsta

    /// The feed sizes these to their cropped poster instead of the full viewport.
    @Test func aTallInstaCardIsFlagged() {
        let vm = card(page(cardShape: .tall),
                      [media(type: "video", url: instaReelURL, position: 0)])
        #expect(vm.isTallInsta)
    }

    @Test func aTallYouTubeShortIsNotAnInstaCard() {
        let vm = card(page(cardShape: .tall),
                      [media(type: "video", url: "https://www.youtube.com/shorts/sh0rt1d",
                             position: 0)])
        #expect(!vm.isTallInsta)
    }

    @Test func aSquareInstaPostIsNotFlagged() {
        let vm = card(page(cardShape: .square),
                      [media(type: "video", url: "https://www.instagram.com/p/CkLm123/",
                             position: 0)])
        #expect(!vm.isTallInsta)
    }

    @Test func aCardWithNoMediaIsNotFlagged() {
        #expect(!card(page(cardShape: .tall), []).isTallInsta)
    }

    /// Only the FIRST media item decides — a tall card whose lead item is an
    /// image isn't sized like a reel even if a reel follows it.
    @Test func onlyTheLeadMediaItemDecides() {
        let vm = card(page(cardShape: .tall), [
            media(type: "image", url: "https://example.com/a.jpg", position: 0),
            media(type: "video", url: instaReelURL, position: 1),
        ])
        #expect(!vm.isTallInsta)
    }

    // MARK: - Compose preview initialiser

    @Test func previewCardCarriesTheScrapedFrameAndHandle() {
        let posterURL = URL(string: "https://scontent.cdninstagram.com/cover.jpg")!
        let vm = CardViewModel(previewing: .insta(id: "CkLm123", kind: .reel),
                               author: author, title: "T", caption: "C",
                               captionStyle: .inkBand, cardShape: .tall,
                               instaPoster: .direct(posterURL), handle: "infinite_mantra",
                               focus: 0.3)
        #expect(vm.title == "T")
        #expect(vm.caption == "C")
        #expect(vm.captionStyle == .inkBand)
        #expect(vm.cardShape == .tall)
        #expect(vm.isTallInsta)

        guard case .video(let source, let poster, let handle, let focus) = vm.media[0] else {
            #expect(Bool(false), "a preview card always has exactly one video item")
            return
        }
        #expect(source == .insta(id: "CkLm123", kind: .reel))
        #expect(handle == "infinite_mantra")
        #expect(focus == 0.3)
        // Direct, not stored: the fresh scrape loads without a signing round trip.
        guard case .direct(let url)? = poster else {
            #expect(Bool(false), "expected a directly-loadable poster")
            return
        }
        #expect(url == posterURL)
    }

    @Test func previewCardDefaultsToACenteredCropAndNoPoster() {
        let vm = CardViewModel(previewing: .youtube(id: "abc123XYZ00"), author: author,
                               title: nil, caption: nil, captionStyle: .paperPlate,
                               cardShape: .wide)
        guard case .video(_, let poster, let handle, let focus) = vm.media[0] else { return }
        #expect(poster == nil)
        #expect(handle == nil)
        #expect(focus == 0.5)
        #expect(!vm.isTallInsta)   // wide, so never reel-sized
    }

    @Test func previewCardsGetDistinctIds() {
        let make = {
            CardViewModel(previewing: .youtube(id: "abc123XYZ00"), author: self.author,
                          title: nil, caption: nil, captionStyle: .paperPlate, cardShape: .wide)
        }
        #expect(make().id != make().id)
    }

    // MARK: - Magazine → cards

    @Test func aMagazineMapsEveryPageToOneCardInOrder() {
        let magazine = Magazine.sample
        #expect(magazine.cards.count == magazine.pages.count)
        #expect(magazine.cards.map(\.id) == magazine.pages.map(\.page.id))
    }

    @Test func contributorsAreDistinctAuthorsInFirstAppearanceOrder() {
        let a = Self.user("A"), b = Self.user("B")
        let magazine = Magazine(
            issue: Issue(id: UUID(), circleId: UUID(), publishDate: "2026-07-25",
                         isLive: true, createdAt: nil),
            pages: [
                MagazinePage(page: page(), pageMedia: [], author: a),
                MagazinePage(page: page(), pageMedia: [], author: b),
                MagazinePage(page: page(), pageMedia: [], author: a),   // repeat
                MagazinePage(page: page(), pageMedia: [], author: nil),  // anonymous
            ])
        #expect(magazine.contributors.map(\.id) == [a.id, b.id])
    }
}
