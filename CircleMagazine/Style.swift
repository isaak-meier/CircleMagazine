//
//  Style.swift
//  CircleMagazine
//
//  The design foundation: a 4-based spacing scale, the editorial print palette
//  (from the card-feed mockup), card radii, and type roles. Semantic names stay
//  constant — only the values would change if we ever theme.
//

import SwiftUI

enum Style {
    /// Spacing scale — everything is a multiple of 4.
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 28
    }

    // Print palette (from the mockup).
    static let paper   = Color(hex: 0xF8F7F4)  // card surface
    static let ink     = Color(hex: 0x0D0D0D)  // primary text
    static let rule    = Color(hex: 0xE0DDD7)  // hairline dividers
    static let meta    = Color(hex: 0x7A7672)  // secondary text
    static let edition = Color(hex: 0x1A1A2E)  // edition stamp / accents
    static let chrome  = Color(hex: 0xECEAE7)  // app background behind cards

    /// Behind a member's initials when they have no avatar image. Picked by user
    /// id, so the same person is the same colour on every screen.
    static let avatarColors: [Color] = [
        Color(hex: 0x3E6E8E), Color(hex: 0x8E5A3E), Color(hex: 0x4A7A52), Color(hex: 0x6A5A8E),
    ]

    // Radii.
    static let cardRadius: CGFloat = 20
    static let mediaRadius: CGFloat = 12

    // Type roles.
    static let wordmark  = Font.system(size: 28, weight: .bold, design: .serif)
    static let cardTitle = Font.system(size: 19, weight: .bold, design: .serif)
    static let pullQuote = Font.system(size: 17, design: .serif)
    static let field     = Font.system(size: 16)                     // text input
    static let button    = Font.system(size: 15, weight: .semibold)  // primary action
    static let stamp     = Font.system(size: 10.5, weight: .medium)  // edition date stamp
    static let body      = Font.system(size: 13)                     // secondary body / captions / errors
    static let byline    = Font.system(size: 13, weight: .semibold)  // card author name / avatar initial
    static let link      = Font.system(size: 13, weight: .medium)    // quiet secondary action
    static let eyebrow   = Font.system(size: 9, weight: .semibold)   // small-caps section label
}

extension View {
    /// Feed card width: full width less a side margin.
    func feedCardWidth() -> some View {
        containerRelativeFrame(.horizontal) { w, _ in w - 2 * Style.Space.md }
    }

    /// Full-screen feed card: `feedCardWidth` plus the viewport height less the
    /// next-card peek. The video fills whatever's left above the fixed-height
    /// plate. Cards that size to their own media use `feedCardWidth` +
    /// `feedCardPage` instead, keeping the page while not filling it.
    func feedCardFrame() -> some View {
        feedCardWidth()
            .containerRelativeFrame(.vertical) { h, _ in h - Style.Space.xxl - Style.Space.sm }
    }

    /// A full-height page with this card centred in it. Same height as
    /// `feedCardFrame`, so every card is one swipe whatever its own height.
    /// `fixedSize` first, because a card is greedy vertically by default and
    /// would otherwise swallow the page instead of sitting in the middle of it.
    func feedCardPage() -> some View {
        fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity)
            .containerRelativeFrame(.vertical) { h, _ in h - Style.Space.xxl - Style.Space.sm }
    }
}

extension Color {
    /// Build a color from a 0xRRGGBB literal — lets us paste the mockup's hex.
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
