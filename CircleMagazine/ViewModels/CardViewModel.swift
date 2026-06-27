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

    init(from page: MagazinePage) {
        self.id = page.page.id
        self.author = page.author
        self.media = page.pageMedia
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            .map(CardMediaViewModel.init)
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

enum VideoSource {
    case youtubeEmbed(id: String)
    case rawFile(URL)

    init?(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // Is it YouTube? www., m., and bare youtube.com all match.
        if components?.host?.contains("youtube.com") == true {
                // It's YouTube — pull the id from ?v=… ; no id ⇒ bogus link, reject.
            guard let id = components?.queryItems?.first(where: { $0.name == "v" })?.value,
                  !id.isEmpty
            else { return nil }
            self = .youtubeEmbed(id: id)
        } else {
                // Any other valid URL: treat as a directly playable file.
            self = .rawFile(url)
        }
    }
}

enum CardMediaError: LocalizedError {
    case invalidURL
    var errorDescription: String? { "The url could not be parsed" }
}
