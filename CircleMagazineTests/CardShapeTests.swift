//
//  CardShapeTests.swift
//  CircleMagazineTests
//
//  The link → default shape mapping, plus the tolerant decode fallback.
//

import Testing
import Foundation
@testable import CircleMagazine

private func shape(_ string: String) -> CardShape {
    CardShape(mediaURL: URL(string: string)!)
}

struct CardShapeTests {

    @Test func youtubeWatchIsWide() {
        #expect(shape("https://www.youtube.com/watch?v=abc123") == .wide)
    }

    @Test func youtubeShortIsTall() {
        #expect(shape("https://youtube.com/shorts/aB3xK9q") == .tall)
    }

    @Test func instaReelIsTall() {
        #expect(shape("https://www.instagram.com/reel/CkLm123/") == .tall)
        #expect(shape("https://instagram.com/reels/CkLm123") == .tall)
    }

    @Test func instaPostIsSquare() {
        #expect(shape("https://instagram.com/p/XyZ789") == .square)
    }

    @Test func unknownDBValueDecodesToTall() throws {
        let decoded = try JSONDecoder().decode(CardShape.self, from: Data("\"4:3\"".utf8))
        #expect(decoded == .tall)
    }
}
