//
//  Card.swift
//  CircleMagazine
//
//  A card is a Page: an author's post carrying a *combination* of media. The
//  combination picks a fixed-size layout template (see cardTemplate). For now
//  these are hardcoded samples; later they're built from Page + User + PageMedia.
//

import Foundation

struct Card: Identifiable {
    let id: UUID
    let authorName: String
    let authorAvatar: String   // emoji for now
    let title: String
    let excerpt: String
    let tags: [String]
    let media: [PageMedia]     // the page's media combination

    init(from page: MagazinePage) {
        self.id = page.id
        self.authorName = "Anon"
        self.authorName = ""
        self.media = page.widgets
    }
}

/// Which layout template a card's media combination maps to. Every template is
/// the same outer size/style — only the media region differs.
enum CardTemplate {
    case photo        // a single photo hero
    case video        // a video hero
    case photoAudio   // "picture + song"
    case pullquote    // text-only quote
    case fallback     // anything else — stack what's there
}

func cardTemplate(for media: [PageMedia]) -> CardTemplate {
    let types = Set(media.compactMap(\.widgetType))
    if types == [.image]          { return .photo }
    if types == [.video]          { return .video }
    if types == [.image, .audio]  { return .photoAudio }
    if types == [.text]           { return .pullquote }
    return .fallback
}

