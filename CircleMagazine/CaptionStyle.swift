//
//  CaptionStyle.swift
//  CircleMagazine
//
//  How a video page's title bar is treated in the issue. There were four
//  editorial directions (badges 1a–1d from the "Circle Caption Options" design);
//  newsprint won and the other three are gone, so this is a one-case enum: it
//  exists to name the value in the `pages.caption_style` column, not to offer a
//  choice. Old rows still carry "paper_plate" / "immersive" / "ink_band", and
//  they all decode to newsprint.
//

import Foundation

enum CaptionStyle: String, Codable {
    case newsprintKicker = "newsprint_kicker"  // cream plate, red rule + mono kicker

    // Every value in the column reads back as newsprint — including the three
    // styles that no longer exist, and anything a future writer invents.
    init(from decoder: Decoder) throws {
        _ = try decoder.singleValueContainer().decode(String.self)
        self = .newsprintKicker
    }
}
