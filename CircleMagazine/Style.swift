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

    // Radii.
    static let cardRadius: CGFloat = 20
    static let mediaRadius: CGFloat = 12

    // Type roles.
    static let wordmark  = Font.system(size: 28, weight: .bold, design: .serif)
    static let cardTitle = Font.system(size: 19, weight: .bold, design: .serif)
    static let pullQuote = Font.system(size: 17, design: .serif)
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
