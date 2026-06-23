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
    let id = UUID()
    let authorName: String
    let authorAvatar: String   // emoji for now
    let timeText: String
    let title: String
    let excerpt: String
    let tags: [String]
    let media: [PageMedia]     // the page's media combination
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

extension Card {
    /// One card per template — the feed's content until DB wiring lands.
    static let sample: [Card] = {
        func media(_ type: String, url: String? = nil, text: String? = nil) -> PageMedia {
            PageMedia(id: UUID(), pageId: nil, mediaUrl: url, mediaType: type,
                      textContent: text, position: nil, createdAt: nil)
        }
        return [
            Card(authorName: "Isaak Meier", authorAvatar: "🎵",
                 timeText: "Posted this morning",
                 title: "Three weeks off the grid taught me what I actually want",
                 excerpt: "Somewhere around day five, I stopped reaching for my phone out of habit. Not because I was disciplined — there was no signal.",
                 tags: ["Reflection"],
                 media: [media("image", url: "https://picsum.photos/seed/forest/800/600")]),

            Card(authorName: "Phil Beebe", authorAvatar: "🌿",
                 timeText: "2 hours ago",
                 title: "A walk through the old quarter at dawn",
                 excerpt: "The city is a different animal before the cafés open — quieter, softer, almost apologetic about the day ahead.",
                 tags: ["Film", "City"],
                 media: [media("video", url: "https://example.com/walk.mov")]),

            Card(authorName: "Alex Kebbe", authorAvatar: "📷",
                 timeText: "Yesterday",
                 title: "The track that scored my whole summer",
                 excerpt: "Pair it with this photo and you'll understand the mood I've been chasing since June.",
                 tags: ["Music"],
                 media: [media("image", url: "https://picsum.photos/seed/album/800/800"),
                         media("audio", url: "https://example.com/song.mp3")]),

            Card(authorName: "Ava Meier", authorAvatar: "🎧",
                 timeText: "Sunday",
                 title: "On letting things love what they love",
                 excerpt: "A small meditation for a slow morning.",
                 tags: ["Reflection"],
                 media: [media("text", text: "You only have to let the soft animal of your body love what it loves.")]),
        ]
    }()
}
