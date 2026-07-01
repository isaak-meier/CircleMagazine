//
//  CaptionStyle.swift
//  CircleMagazine
//
//  How a video page's title bar is treated in the issue. Four editorial
//  directions from the "Circle Caption Options" design (badges 1a–1d). Stored
//  on pages.caption_style; VideoCard switches its bottom treatment on it.
//

import Foundation

enum CaptionStyle: String, CaseIterable, Codable, Identifiable {
    case paperPlate      = "paper_plate"       // 1a — cream plate, black top rule, YouTube mark
    case immersive       = "immersive"         // 1b — no plate, title over the photo
    case inkBand         = "ink_band"          // 1c — navy plate, cream serif title
    case newsprintKicker = "newsprint_kicker"  // 1d — cream plate, red rule + mono kicker

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paperPlate:      "Paper plate"
        case .immersive:       "Immersive"
        case .inkBand:         "Ink band"
        case .newsprintKicker: "Newsprint"
        }
    }

    // Tolerant decode: an unknown value in the DB falls back to the default
    // rather than failing the whole issue fetch.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CaptionStyle(rawValue: raw) ?? .paperPlate
    }
}
