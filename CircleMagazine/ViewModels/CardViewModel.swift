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

    /// Compose live preview — a card that doesn't exist in the DB yet.
    init(previewing source: VideoSource, author: User?, title: String?, caption: String?,
         captionStyle: CaptionStyle, cardShape: CardShape) {
        self.id = UUID()
        self.media = [.video(source)]
        self.author = author
        self.title = title
        self.caption = caption
        self.captionStyle = captionStyle
        self.cardShape = cardShape
    }
}

/// One renderable piece of a card, transformed from a raw `PageMedia` row.
/// Text/audio are parked — `init?` returns nil for them, so they drop out
/// of the `compactMap` above.
enum CardMediaViewModel {
    case image(URL)
    case video(VideoSource)
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
                    self = .video(videoSource)
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
