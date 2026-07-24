//
//  InstagramEmbedTests.swift
//  CircleMagazineTests
//
//  The embed-page HTML parser: pulling the cover-frame URL and @handle out of
//  Instagram's /embed markup. Fixtures mirror the real page structure (the
//  EmbeddedMediaImage <img> and the UsernameText <span>), including the &amp;
//  entities Instagram puts in its CDN URLs.
//

import Testing
import Foundation
@testable import CircleMagazine

struct InstagramEmbedTests {

    // A trimmed but structurally-real embed page: a profile <img> first (must be
    // ignored), then the EmbeddedMediaImage cover frame, then the handle span.
    private let html = """
    <div class="Header"><img class="Avatar" src="https://scontent.cdninstagram.com/profile.jpg?oh=1&amp;oe=ABC"/></div>
    <img class="EmbeddedMediaImage" alt="Instagram post shared by &#064;infinite_mantra" \
    src="https://scontent-sjc3-1.cdninstagram.com/v/t51/cover.jpg?stp=dst-jpg&amp;_nc_ht=x&amp;oe=6A6754C8" \
    srcset="https://scontent-sjc3-1.cdninstagram.com/v/t51/cover.jpg?w=640 640w"/>
    <div class="CaptionUsername"><a href="https://www.instagram.com/infinite_mantra/">\
    <span class="UsernameText">infinite_mantra</span></a></div>
    """

    @Test func pullsCoverFrameNotProfilePic() {
        let url = InstagramEmbed.parsePosterURL(html)
        // The EmbeddedMediaImage src, with entities decoded — not the avatar.
        #expect(url?.absoluteString == "https://scontent-sjc3-1.cdninstagram.com/v/t51/cover.jpg?stp=dst-jpg&_nc_ht=x&oe=6A6754C8")
    }

    @Test func pullsHandle() {
        #expect(InstagramEmbed.parseHandle(html) == "infinite_mantra")
    }

    @Test func missingMarkupYieldsNil() {
        #expect(InstagramEmbed.parsePosterURL("<html>nope</html>") == nil)
        #expect(InstagramEmbed.parseHandle("<html>nope</html>") == nil)
    }
}
