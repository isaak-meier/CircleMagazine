//
//  VideoCard.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/30/26.
//

import SwiftUI
import WebKit
// Full-bleed video card: video fills the whole card, with the author chip pinned
// top-left and the post's serif title bleeding over the bottom (v2 layout).
// Internal (not private) so Compose can reuse it as the live "how it appears" preview.
struct VideoCard: View {
    let source: VideoSource
    let author: User?
    let caption: String?
    let title: String?

    var body: some View {
        ZStack {
                // Full-bleed media fills the card; chrome sits on top.
            switch source {
                case .youtube(let id): YouTubeThumbnail(id: id)
                case .insta(let id, let kind):   InstaEmbed(id: id, kind: kind)
                case .rawFile:         Color.black   // TODO wire up file playback
            }

                // Dual scrim: darken top (author chip) and bottom (title), clear middle.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.5),  location: 0.0),
                .init(color: .clear,               location: 0.18),
                .init(color: .clear,               location: 0.52),
                .init(color: .black.opacity(0.32), location: 0.74),
                .init(color: .black.opacity(0.82), location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)

            Image(systemName: "play.fill")
                .font(.system(size: 22)).foregroundStyle(Style.ink)
                .padding(20).background(SwiftUI.Circle().fill(.white.opacity(0.94)))
                .allowsHitTesting(false)   // let taps reach the thumbnail underneath

            handle
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

            if let author {
                authorChip(author)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
            }

            if let title {
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18).padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var handle: some View {
        Capsule().fill(.white.opacity(0.6))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
    }

        // Author identity over the top of the media: avatar + name + caption subtitle.
    private func authorChip(_ author: User) -> some View {
        HStack(spacing: 9) {
            SwiftUI.Circle().fill(.white.opacity(0.18))
                .frame(width: 30, height: 30)
                .overlay(SwiftUI.Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                .overlay(Text(author.username.prefix(1)).font(Style.byline).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(author.username).font(Style.byline).foregroundStyle(.white)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }
        }
    }
}

    // YouTube thumbnail that opens the video externally on tap — no in-app playback.
    // Thumbnail URL is predictable from the id, so no API call needed.
private struct YouTubeThumbnail: View {
    let id: String
    @Environment(\.openURL) private var openURL
        // maxresdefault is 16:9 and sharp but 404s for some videos; hqdefault always
        // exists (4:3 with letterbox bars). Try maxres, fall back to hq on failure.
    @State private var useFallback = false

    private var thumbnailURL: URL? {
        let quality = useFallback ? "hqdefault" : "maxresdefault"
        return URL(string: "https://img.youtube.com/vi/\(id)/\(quality).jpg")
    }

    var body: some View {
            // Color.black defines the frame; the image overlays and is clipped to it,
            // so scaledToFill can't push past the card bounds.
        Color.black
            .overlay {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure where !useFallback:
                            Color.clear.onAppear { useFallback = true }   // retry with hqdefault
                        default:
                            Color.clear
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = URL(string: "https://www.youtube.com/watch?v=\(id)") { openURL(url)
                }
            }
    }
}

private struct InstaThumbnail: View {
    let id: String
    let kind: InstagramContentType
    @Environment(\.openURL) private var openURL

    var body: some View {
        LinearGradient(colors: [Color.purple, Color.orange, Color.pink], startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 1, y: 1))
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = URL(string: "https://www.instagram.com/\(kind.rawValue)/\(id)/") {
                    openURL(url)
                }
            }
    }
}

// Path A: plays the reel inline via Instagram's official embed in a WKWebView.
// Same (id:, kind:) signature as InstaThumbnail, so switching the two on the
// VideoCard switch line above is a one-identifier change.
private struct InstaEmbed: View {
    let id: String
    let kind: InstagramContentType

    private var embedURL: URL? {
        // Instagram's embed endpoint serves /reel/ and /p/ but not the plural
        // /reels/ — map reels onto reel so reels-links embed too.
        let segment = kind == .post ? "p" : "reel"
        return URL(string: "https://www.instagram.com/\(segment)/\(id)/embed")
    }

    var body: some View {
        if let embedURL {
            InstaWebView(url: embedURL)
        } else {
            Color.black
        }
    }
}

private struct InstaWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.load(URLRequest(url: url))
    }
}

#Preview("InstaCard") {
    VideoCard(source: .insta(id: "DZ30GywAbc7", kind: .reel), author: nil, caption: nil, title: nil)
}
