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
    /// Photos are stored under their circle's folder, so a test path looks like
    /// the real thing rather than like a URL.
    private let circleFolder = "0C1E1E7A-0000-0000-0000-00000000C1AB"
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
        case .link:     "link"
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

    /// The stored path behind an `.image`, or nil if it wasn't one.
    private func storedPath(_ media: CardMediaViewModel) -> String? {
        if case .image(.stored(let path)) = media { return path }
        return nil
    }

    @Test func mediaIsSortedByPosition() {
        let vm = card(page(), [
            media(type: "image", url: "\(circleFolder)/c.jpg", position: 2),
            media(type: "image", url: "\(circleFolder)/a.jpg", position: 0),
            media(type: "image", url: "\(circleFolder)/b.jpg", position: 1),
        ])
        let names = vm.media.map { storedPath($0).map { ($0 as NSString).lastPathComponent } ?? "?" }
        #expect(names == ["a.jpg", "b.jpg", "c.jpg"])
    }

    /// A null position sorts as 0, so legacy rows land first rather than crashing
    /// the sort or dropping out.
    @Test func nullPositionSortsAsZero() {
        let vm = card(page(), [
            media(type: "image", url: "\(circleFolder)/second.jpg", position: 1),
            media(type: "image", url: "\(circleFolder)/first.jpg", position: nil),
        ])
        #expect(storedPath(vm.media[0]) == "\(circleFolder)/first.jpg")
    }

    @Test func everyMediaRowBecomesExactlyOneRenderableItem() {
        let vm = card(page(), [
            media(type: "image", url: "\(circleFolder)/a.jpg", position: 0),
            media(type: "video", url: youtubeURL, position: 1),
            media(type: "text", url: nil, position: 2),
        ])
        #expect(vm.media.count == 3)
        #expect(vm.media.map(label) == ["image", "video", "fallback"])
    }

    // MARK: - Media mapping: images

    /// A photo's `media_url` is a storage path, not a URL — it must survive
    /// intact for signing, not get run through URL parsing.
    @Test func anImageRowKeepsItsStoragePath() {
        let vm = card(page(), [media(type: "image", url: "\(circleFolder)/a.jpg", position: 0)])
        #expect(storedPath(vm.media[0]) == "\(circleFolder)/a.jpg")
    }

    /// An image row with no path can't be signed, so it falls back rather than
    /// rendering a card pointing at nothing.
    @Test func anImageRowWithNoPathFallsBack() {
        let vm = card(page(), [media(type: "image", url: nil, position: 0)])
        #expect(label(vm.media[0]) == "fallback")
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

    // MARK: - hugsItsMedia
    //
    // Which cards the feed sizes to their media and centres, instead of
    // stretching to fill the page. Video has a shape of its own and filling can
    // only crop it; a photo has no shape until it loads, so it fills.

    /// The feed sizes these to their cropped poster instead of the full viewport.
    @Test func aTallInstaCardHugsItsMedia() {
        let vm = card(page(cardShape: .tall),
                      [media(type: "video", url: instaReelURL, position: 0)])
        #expect(vm.hugsItsMedia)
    }

    /// A YouTube embed is 16:9 whatever shape the author picked — filling a
    /// portrait card would crop through burned-in captions and the player's
    /// own chrome, so every YouTube card hugs regardless of `cardShape`.
    @Test func aYouTubeCardHugsItsMediaAtEveryShape() {
        for shape in CardShape.allCases {
            let vm = card(page(cardShape: shape),
                          [media(type: "video", url: "https://www.youtube.com/shorts/sh0rt1d",
                                 position: 0)])
            #expect(vm.hugsItsMedia)
        }
    }

    /// Instagram is the exception: only the tall reel crop hugs. A square post
    /// has no tall poster to hug, so it fills like anything else.
    @Test func aSquareInstaPostDoesNotHug() {
        let vm = card(page(cardShape: .square),
                      [media(type: "video", url: "https://www.instagram.com/p/CkLm123/",
                             position: 0)])
        #expect(!vm.hugsItsMedia)
    }

    /// A photo's aspect isn't known until it loads, so a photo card fills the
    /// page and crops rather than resizing under the reader.
    @Test func aPhotoCardDoesNotHug() {
        let vm = card(page(cardShape: .tall),
                      [media(type: "image", url: "https://example.com/a.jpg", position: 0)])
        #expect(!vm.hugsItsMedia)
    }

    @Test func aCardWithNoMediaDoesNotHug() {
        #expect(!card(page(cardShape: .tall), []).hugsItsMedia)
    }

    /// Only the FIRST media item decides — a tall card whose lead item is an
    /// image isn't sized like a reel even if a reel follows it.
    @Test func onlyTheLeadMediaItemDecides() {
        let vm = card(page(cardShape: .tall), [
            media(type: "image", url: "https://example.com/a.jpg", position: 0),
            media(type: "video", url: instaReelURL, position: 1),
        ])
        #expect(!vm.hugsItsMedia)
    }

    // MARK: - Feed grouping
    //
    // An edition reads as sections: every YouTube card, then every reel, then
    // the rest. Cards in a group are the same height as each other, so the feed
    // stops changing format every swipe.

    /// One page per medium, deliberately interleaved in the issue, so a feed
    /// that just echoed page order would fail this.
    private func mixedMagazine() -> Magazine {
        func p(_ type: String, _ url: String, _ title: String) -> MagazinePage {
            MagazinePage(page: page(title: title),
                         pageMedia: [media(type: type, url: url, position: 0)],
                         author: author)
        }
        return Magazine(
            issue: Issue(id: UUID(), circleId: UUID(), publishDate: "2026-08-01",
                         isLive: nil, createdAt: nil),
            pages: [
                p("image", "\(circleFolder)/one.jpg", "photo A"),
                p("video", instaReelURL, "reel A"),
                p("video", youtubeURL, "tube A"),
                p("image", "\(circleFolder)/two.jpg", "photo B"),
                p("video", "https://www.youtube.com/watch?v=zzz999AAA11", "tube B"),
                p("video", "https://www.instagram.com/reel/Wxyz789/", "reel B"),
            ])
    }

    @Test func theFeedGroupsCardsByMedium() {
        #expect(mixedMagazine().cards().map(\.medium) ==
                [.youtube, .youtube, .instagram, .instagram, .other, .other])
    }

    /// Grouping must not reshuffle within a group — the issue's own page order
    /// still decides which YouTube card comes first.
    @Test func groupingKeepsPageOrderInsideEachGroup() {
        #expect(mixedMagazine().cards().map(\.title) ==
                ["tube A", "tube B", "reel A", "reel B", "photo A", "photo B"])
    }

    @Test func groupingLosesNoPages() {
        let magazine = mixedMagazine()
        #expect(magazine.cards().count == magazine.pages.count)
    }

    // MARK: - Blank pages

    /// A page with nothing to draw is a blank sheet of paper in the feed — old
    /// pages with no media rows look like this, and so does one whose media a
    /// policy withheld.
    @Test func theFeedDropsPagesWithNothingToRender() {
        let magazine = Magazine(
            issue: Issue(id: UUID(), circleId: UUID(), publishDate: "2026-08-01",
                         isLive: nil, createdAt: nil),
            pages: [
                MagazinePage(page: page(title: "real"),
                             pageMedia: [media(type: "image", url: "\(circleFolder)/a.jpg", position: 0)],
                             author: author),
                MagazinePage(page: page(title: "no media rows at all"),
                             pageMedia: [], author: author),
                // "audio" is a parked kind — it lands on `.fallback`, which draws
                // nothing, same as a row the reader isn't allowed to see.
                MagazinePage(page: page(title: "nothing we can draw"),
                             pageMedia: [media(type: "audio", url: "https://example.com/a.m4a",
                                               position: 0)],
                             author: author),
            ])
        #expect(magazine.cards().map(\.title) == ["real"])
    }

    @Test func aPageWithOnlyAFallbackRowHasNothingToRender() {
        #expect(!card(page(), [media(type: "audio", url: "https://example.com/a.m4a", position: 0)])
            .hasRenderableMedia)
        #expect(!card(page(), []).hasRenderableMedia)
        #expect(card(page(), [media(type: "video", url: youtubeURL, position: 0)])
            .hasRenderableMedia)
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
        #expect(vm.hugsItsMedia)

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
        #expect(vm.hugsItsMedia)   // YouTube is 16:9 even on a wide card
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
        #expect(magazine.cards().count == magazine.pages.count)
        #expect(magazine.cards().map(\.id) == magazine.pages.map(\.page.id))
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
