//
//  CardShape.swift
//  CircleMagazine
//
//  The card's media aspect ratio, defaulted from the pasted link (no picker):
//  YouTube watch → wide, YouTube Short / Insta reel → tall, Insta post → square.
//  Stored on pages.card_shape; VideoCard sizes its media region from it.
//

import Foundation

enum CardShape: String, Codable {
    case wide   = "16:9"
    case tall   = "9:16"
    case square = "1:1"

    var ratio: CGFloat {
        switch self {
        case .wide:   16.0 / 9.0
        case .tall:   9.0 / 16.0
        case .square: 1
        }
    }

    // Tolerant decode: unknown DB value → .tall, which renders exactly
    // like every pre-existing row (full-bleed).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardShape(rawValue: raw) ?? .tall
    }

    // Default from the pasted link.
    init(mediaURL url: URL) {
        let host = url.host ?? ""
        if host.contains("instagram") {
            self = url.pathComponents.contains("p") ? .square : .tall   // post vs reel/reels
        } else if url.pathComponents.contains("shorts") {
            self = .tall
        } else {
            self = .wide   // regular YouTube, raw files
        }
    }
}
