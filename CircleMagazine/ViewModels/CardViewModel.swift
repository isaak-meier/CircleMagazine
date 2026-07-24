//
//  Card.swift
//  CircleMagazine
//
//  A card is a Page: an author's post carrying media. CardViewModel transforms
//  each raw PageMedia row into a CardMediaViewModel the views render directly.

import Foundation

struct CardViewModel: Identifiable {
    let id: UUID
    let media: [CardMediaViewModel]     // the page's media, in position order
    let author: User?
    let title: String?
    let caption: String?
    let captionStyle: CaptionStyle
    let cardShape: CardShape

    init(from page: MagazinePage) {
        self.id = page.page.id
        self.author = page.author
        self.title = page.page.title
        self.caption = page.page.caption
        self.captionStyle = page.page.captionStyle ?? .paperPlate
        self.cardShape = page.page.cardShape ?? .tall
        self.media = page.pageMedia
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            .map(CardMediaViewModel.init)
    }

    /// A tall Instagram reel: the feed lets these size to their cropped poster
    /// rather than stretching them to full viewport height.
    var isTallInsta: Bool {
        guard cardShape == .tall, case .video(.insta, _, _, _) = media.first else { return false }
        return true
    }

    /// Compose live preview — a card that doesn't exist in the DB yet. For an
    /// insta preview, `instaPoster`/`handle` carry the freshly-scraped frame so
    /// the preview matches the feed card (no re-host round trip needed yet).
    init(previewing source: VideoSource, author: User?, title: String?, caption: String?,
         captionStyle: CaptionStyle, cardShape: CardShape,
         instaPoster: InstaPoster? = nil, handle: String? = nil, focus: Double = 0.5) {
        self.id = UUID()
        self.media = [.video(source, instaPoster, handle: handle, focus: focus)]
        self.author = author
        self.title = title
        self.caption = caption
        self.captionStyle = captionStyle
        self.cardShape = cardShape
    }
}

/// Where an Instagram card's cover frame comes from: a path in our private
/// `posters` bucket (feed — needs signing) or a directly-loadable URL (compose
/// preview — the fresh scrape, still valid).
enum InstaPoster {
    case stored(path: String)
    case direct(URL)
}

/// One renderable piece of a card, transformed from a raw `PageMedia` row.
/// Text/audio are parked — `init?` returns nil for them, so they drop out
/// of the `compactMap` above.
enum CardMediaViewModel {
    case image(URL)
    // insta carries its re-hosted poster + @handle + crop focus; nil/center for YouTube.
    case video(VideoSource, InstaPoster?, handle: String?, focus: Double)
    case fallback(CardMediaError?)

    init(_ media: PageMedia) {
        guard let raw = media.mediaUrl, let url = URL(string: raw) else {
            self = .fallback(CardMediaError.invalidURL)
            return
        }
        switch media.mediaType {
            case "image": self = .image(url)
            case "video":
                if let videoSource = VideoSource(url) {
                    let poster = media.posterUrl.map(InstaPoster.stored)
                    self = .video(videoSource, poster, handle: media.textContent,
                                  focus: media.posterFocus ?? 0.5)
                } else {
                    self = .fallback(CardMediaError.invalidURL)
                }
            default: self = .fallback(nil)
        }
    }
}
enum CardMediaError: LocalizedError {
    case invalidURL
    var errorDescription: String? { "The url could not be parsed" }
}
