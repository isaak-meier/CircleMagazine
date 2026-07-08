//
//  VideoSourceTests.swift
//  CircleMagazineTests
//
//  Exhaustive coverage of VideoSource.init?(_ url: URL).
//

import Testing
import Foundation
@testable import CircleMagazine

private func source(_ string: String) -> VideoSource? {
    VideoSource(URL(string: string)!)
}

struct VideoSourceTests {

    // MARK: youtu.be short links

    @Test func youtuBeShortLink() {
        #expect(source("https://youtu.be/aB3xK9q") == .youtube(id: "aB3xK9q"))
    }

    @Test func youtuBeWithQuery() {
        // Query (timestamp) is not part of pathComponents, so id is still clean.
        #expect(source("https://youtu.be/aB3xK9q?t=42") == .youtube(id: "aB3xK9q"))
    }

    @Test func youtuBeSubdomain() {
        #expect(source("https://www.youtu.be/aB3xK9q") == .youtube(id: "aB3xK9q"))
    }

    @Test func youtuBeRootSlashOnly() {
        // pathComponents == ["/"], count is not > 1 -> reject.
        #expect(source("https://youtu.be/") == nil)
    }

    @Test func youtuBeNoPath() {
        // pathComponents == [], last is nil -> reject.
        #expect(source("https://youtu.be") == nil)
    }

    // MARK: youtube.com watch links

    @Test func youtubeWatchLink() {
        #expect(source("https://www.youtube.com/watch?v=abc123") == .youtube(id: "abc123"))
    }

    @Test func youtubeWatchNoSubdomain() {
        #expect(source("https://youtube.com/watch?v=abc123") == .youtube(id: "abc123"))
    }

    @Test func youtubeMobileSubdomain() {
        #expect(source("https://m.youtube.com/watch?v=abc123") == .youtube(id: "abc123"))
    }

    @Test func youtubeVAmongOtherParams() {
        #expect(source("https://youtube.com/watch?list=PL9&v=abc123&t=5") == .youtube(id: "abc123"))
    }

    @Test func youtubeNoVParam() {
        #expect(source("https://youtube.com/watch?list=PL9") == nil)
    }

    @Test func youtubeNoQueryAtAll() {
        #expect(source("https://youtube.com/watch") == nil)
    }

    @Test func youtubeEmptyVParam() {
        #expect(source("https://youtube.com/watch?v=") == nil)
    }

    // MARK: youtube.com shorts links

    @Test func youtubeShorts() {
        #expect(source("https://www.youtube.com/shorts/aB3xK9q") == .youtube(id: "aB3xK9q"))
    }

    @Test func youtubeShortsWithQuery() {
        #expect(source("https://youtube.com/shorts/aB3xK9q?feature=share") == .youtube(id: "aB3xK9q"))
    }

    @Test func youtubeShortsMarkerButNoID() {
        // "shorts" is the last component -> index+1 out of range -> reject.
        #expect(source("https://youtube.com/shorts/") == nil)
    }

    // MARK: instagram links -- id + content-type kind

    @Test func instaReel() {
        #expect(source("https://www.instagram.com/reel/CkLm123/") == .insta(id: "CkLm123", kind: .reel))
    }

    @Test func instaReelsPlural() {
        #expect(source("https://instagram.com/reels/CkLm123") == .insta(id: "CkLm123", kind: .reels))
    }

    @Test func instaPost() {
        #expect(source("https://instagram.com/p/XyZ789") == .insta(id: "XyZ789", kind: .post))
    }

    @Test func instaWithTrailingSlash() {
        #expect(source("https://instagram.com/p/XyZ789/") == .insta(id: "XyZ789", kind: .post))
    }

    @Test func instaWithUserPrefix() {
        // /username/reel/ID -- firstIndex finds the "reel" marker, id follows it.
        #expect(source("https://instagram.com/someuser/reel/CkLm123") == .insta(id: "CkLm123", kind: .reel))
    }

    @Test func instaMarkerButNoID() {
        // "reel" is the last component -> index+1 out of range -> reject.
        #expect(source("https://instagram.com/reel/") == nil)
    }

    @Test func instaNoMarker() {
        // A plain profile URL has no p/reel/reels marker -> reject.
        #expect(source("https://instagram.com/someuser") == nil)
    }

    // MARK: raw file fallback

    @Test func rawHTTPFile() {
        let url = URL(string: "https://example.com/video.mp4")!
        #expect(VideoSource(url) == .rawFile(url))
    }

    @Test func rawLocalFile() {
        // file:// URLs have no host -> falls through to rawFile.
        let url = URL(string: "file:///Users/isaak/movie.mov")!
        #expect(VideoSource(url) == .rawFile(url))
    }

    @Test func rawUnrelatedHost() {
        let url = URL(string: "https://vimeo.com/123456")!
        #expect(VideoSource(url) == .rawFile(url))
    }
}

// Equatable purely for test assertions.
extension VideoSource: @retroactive Equatable {
    public static func == (lhs: VideoSource, rhs: VideoSource) -> Bool {
        switch (lhs, rhs) {
        case let (.youtube(a), .youtube(b)): return a == b
        case let (.insta(idA, kindA), .insta(idB, kindB)): return idA == idB && kindA == kindB
        case let (.rawFile(a), .rawFile(b)): return a == b
        default: return false
        }
    }
}
