//
//  VideoCard.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/30/26.
//

import SwiftUI
import WebKit
// Video card: media sized by CardShape (full-bleed for tall, top-pinned for
// wide/square), author chip top-left, title treatment driven by CaptionStyle.
// Rendered only via CardView — Compose previews through CardView too.
struct VideoCard: View {
    let source: VideoSource
    let author: User?
    let caption: String?
    let title: String?
    var captionStyle: CaptionStyle = .paperPlate
    var cardShape: CardShape = .tall

    // The line the plate/overlay sets in serif. Falls back to the note when a
    // video has no fetched title; nil ⇒ no plate at all (just the media).
    private var displayTitle: String? {
        let t = title ?? caption
        return (t?.isEmpty ?? true) ? nil : t
    }

    var body: some View {
        Group {
            switch captionStyle {
            case .immersive: immersiveCard
            default:         platedCard   // paperPlate / inkBand / newsprintKicker
            }
        }
        // .top pins wide/square media (+ plate) to the card top; the leftover
        // card area below shows the card's paper background. Tall fills anyway.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Layouts

    // 1a / 1c / 1d — fixed-height media on top, a caption plate underneath.
    // The plate carries the author chip, so it renders even with no title.
    private var platedCard: some View {
        VStack(spacing: 0) {
            mediaRegion(scrim: topScrim)
            if displayTitle != nil || author != nil { plate }
        }
    }

    // 1b — full-bleed media with the title floating over the bottom. No plate,
    // so the author chip stays overlaid on the media here.
    private var immersiveCard: some View {
        mediaRegion(scrim: immersiveScrim) {
            if let author {
                authorChip(author, tint: .white)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
            }
            if let displayTitle {
                VStack(alignment: .leading, spacing: 9) {
                    kicker(markSize: 18, color: .white.opacity(0.85))
                    Text(displayTitle)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18).padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Media region (shared)

    private func mediaRegion(scrim: some View,
                             @ViewBuilder overlay: () -> some View = { EmptyView() }) -> some View {
        ZStack {
            media
            scrim.allowsHitTesting(false)

            Image(systemName: "play.fill")
                .font(.system(size: 22)).foregroundStyle(Style.ink)
                .padding(20).background(SwiftUI.Circle().fill(.white.opacity(0.94)))
                .allowsHitTesting(false)   // let taps reach the thumbnail underneath

            handle
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

            overlay()
        }
        .modifier(ShapeFrame(shape: cardShape))
        .clipped()
    }

    // Tall fills the card (as before the shape axis existed); wide/square lock
    // the media region to a fixed aspect ratio.
    private struct ShapeFrame: ViewModifier {
        let shape: CardShape
        func body(content: Content) -> some View {
            switch shape {
            case .tall:
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .wide, .square:
                content.aspectRatio(shape.ratio, contentMode: .fit)
                       .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var media: some View {
        switch source {
        case .youtube(let id):         YouTubeEmbed(id: id)   // was YouTubeThumbnail — one-identifier swap back
        case .insta(let id, let kind): InstaEmbed(id: id, kind: kind)
        case .rawFile:                 Color.black   // TODO wire up file playback
        }
    }

    // Darken just the top so the author chip reads; the plate carries the title.
    private var topScrim: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.5),  location: 0.0),
            .init(color: .black.opacity(0.18), location: 0.22),
            .init(color: .clear,               location: 0.42),
        ], startPoint: .top, endPoint: .bottom)
    }

    // Bottom-heavy scrim for the full-bleed title (1b).
    private var immersiveScrim: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.5),  location: 0.0),
            .init(color: .clear,               location: 0.20),
            .init(color: .clear,               location: 0.52),
            .init(color: .black.opacity(0.3),  location: 0.72),
            .init(color: .black.opacity(0.85), location: 1.0),
        ], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Plates

    @ViewBuilder
    private var plate: some View {
        switch captionStyle {
        case .inkBand:         inkBandPlate
        case .newsprintKicker: newsprintPlate
        default:               paperPlate
        }
    }

    // 1a — cream plate, black top rule, source mark + serif title, author below.
    private var paperPlate: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                sourceMark(size: 26)
                plateTitle(color: Style.ink)
                Spacer(minLength: 0)
            }
            if let author { authorChip(author, tint: Style.ink) }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.paper)
        .overlay(alignment: .top) { Rectangle().fill(Style.ink).frame(height: 2) }
    }

    // 1c — navy plate, mono kicker, cream serif title, author below.
    private var inkBandPlate: some View {
        VStack(alignment: .leading, spacing: 8) {
            kicker(markSize: 17, color: Color(hex: 0x9A9AC0))
            plateTitle(color: Style.paper)
            if let author { authorChip(author, tint: .white).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .background(Style.edition)
    }

    // 1d — cream plate, red rule, "VIDEO · author" mono kicker over serif title.
    private var newsprintPlate: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xFF0000)).frame(width: 3)
            VStack(alignment: .leading, spacing: 7) {
                monoKicker("Video · \(author?.username ?? "Circle")", color: Style.meta)
                plateTitle(color: Style.ink)
                if let author { authorChip(author, tint: Style.ink).padding(.top, 3) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .background(Style.paper)
    }

    private func plateTitle(color: Color) -> some View {
        Text(displayTitle ?? "")
            .font(.system(size: 18, weight: .bold, design: .serif))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Bits

    private var handle: some View {
        Capsule().fill(.white.opacity(0.6))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
    }

    // Author identity: avatar + name + caption subtitle. Tint is .white over
    // media / the navy plate, Style.ink on the cream plates.
    private func authorChip(_ author: User, tint: Color) -> some View {
        HStack(spacing: 9) {
            SwiftUI.Circle().fill(tint.opacity(0.18))
                .frame(width: 30, height: 30)
                .overlay(SwiftUI.Circle().stroke(tint.opacity(0.45), lineWidth: 1))
                .overlay(Text(author.username.prefix(1)).font(Style.byline).foregroundStyle(tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(author.username).font(Style.byline).foregroundStyle(tint)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10.5)).foregroundStyle(tint.opacity(0.82))
                        .lineLimit(1)
                }
            }
        }
    }

    // A "▶ WATCH" mono line, used by 1b/1c. ponytail: no duration — oEmbed
    // doesn't return it, so we show the verb without a runtime.
    private func kicker(markSize: CGFloat, color: Color) -> some View {
        HStack(spacing: 8) {
            sourceMark(size: markSize)
            Text("Watch".uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.6).foregroundStyle(color)
        }
    }

    private func monoKicker(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(1.6).foregroundStyle(color)
    }

    // Red YouTube glyph for YouTube posts; nothing for other sources.
    @ViewBuilder
    private func sourceMark(size: CGFloat) -> some View {
        if case .youtube = source {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(Color(hex: 0xFF0000))
                .frame(width: size, height: size * 0.7)
                .overlay(Image(systemName: "play.fill")
                    .font(.system(size: size * 0.34)).foregroundStyle(.white))
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

// Plays the video inline via YouTube's embed in a WKWebView. Same (id:) signature
// as YouTubeThumbnail, so switching the two on the VideoCard switch line is a
// one-identifier change. Old thumbnail-only behavior kept above.
private struct YouTubeEmbed: View {
    let id: String

    // Loading the embed URL directly gives YouTube a null/opaque origin and it
    // throws "player configuration error". Wrapping the iframe in our own HTML
    // and loading it with a real baseURL supplies the origin the player needs.
    private var html: String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;background:#000;height:100%}iframe{border:0;width:100%;height:100%;position:absolute}</style>
        </head><body>
        <iframe src="https://www.youtube.com/embed/\(id)?playsinline=1&origin=https://circlemagazine.app"
                allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>
        </body></html>
        """
    }

    var body: some View {
        WebEmbedView(html: html, baseURL: URL(string: "https://circlemagazine.app"))
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
            WebEmbedView(url: embedURL)
        } else {
            Color.black
        }
    }
}

private struct WebEmbedView: UIViewRepresentable {
    enum Content {
        case url(URL)
        case html(String, baseURL: URL?)
    }
    let content: Content

    init(url: URL) { content = .url(url) }
    init(html: String, baseURL: URL?) { content = .html(html, baseURL: baseURL) }

    func makeUIView(context: Context) -> WKWebView {
        // Inline playback config is required or YouTube demands fullscreen and
        // taps do nothing; matches how the iframe embed expects to run.
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        switch content {
        case .url(let url):
            webView.load(URLRequest(url: url))
        case .html(let html, let baseURL):
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }
}

#Preview("InstaCard") {
    VideoCard(source: .insta(id: "DZ30GywAbc7", kind: .reel), author: nil, caption: nil, title: nil)
}
