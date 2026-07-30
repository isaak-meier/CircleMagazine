//
//  VideoCard.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/30/26.
//

import SwiftUI

// The crop window a tall Instagram reel poster is shown in, as width : height.
// A 9:16 reel is cropped to this; the author picks which vertical band shows.
// Tune to taste — smaller height (bigger number) makes the reel card shorter.
private let instaReelAspect: CGFloat = 1.0

// Video card: media sized to the source's own shape, author chip top-left,
// title treatment driven by CaptionStyle.
// Rendered only via CardView — Compose previews through CardView too.
struct VideoCard: View {
    let source: VideoSource
    var cardShape: CardShape = .tall
    let author: User?
    let caption: String?
    let title: String?
    var captionStyle: CaptionStyle = .paperPlate
    /// 1a's Comment button opens the comments sheet (wired by CardView). Nil in
    /// previews, where the button is inert.
    var onComment: (() -> Void)? = nil
    /// True when this is the card the feed is snapped to — the YouTube embed
    /// autoplays while active and pauses when scrolled away.
    var isActive: Bool = false
    /// Optional control shown at the right of the poster row (the delete menu).
    var trailingAccessory: AnyView? = nil
    /// Instagram-only: the re-hosted cover frame + creator @handle. The card
    /// draws a native still that taps out to the reel (IG never plays inline).
    var instaPoster: MediaRef? = nil
    var instaHandle: String? = nil
    /// The edition's VM — signs the poster's storage path for display; nil in previews.
    var issue: IssueViewModel? = nil
    /// Author-chosen vertical crop for the reel poster (0 top…1 bottom).
    var instaFocus: Double = 0.5
    /// Compose only: dragging the poster reports a new crop focus. Its presence
    /// switches the card into edit mode (drag to reposition, no tap-out).
    var onInstaFocusChange: ((Double) -> Void)? = nil

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
        // Fill the card; the media stretches to take the space above the plate.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Layouts

    // 1a / 1c / 1d — fixed-height media on top, a caption plate underneath.
    // The plate carries the author chip, so it renders even with no title.
    private var platedCard: some View {
        VStack(spacing: 0) {
            mediaRegion(scrim: Color.clear)
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

            overlay()
        }
        .modifier(ShapeFrame(contentAspect: contentAspect))
        .clipped()
    }

    // Each medium is shown at the shape it was shot in: a YouTube video is 16:9
    // and a tall reel crops to `instaReelAspect`. The card then sizes to that
    // rather than stretching the media to fill a viewport-tall page — filling
    // would crop through burned-in captions and the player's own chrome.
    private var contentAspect: CGFloat? {
        switch source {
        case .youtube: 16.0 / 9.0
        case .insta:   cardShape == .tall ? instaReelAspect : nil
        case .rawFile: nil
        }
    }

    // Sizes the media to `contentAspect` so the card can hug it. Nil ⇒ fill the
    // card (a wide/square reel, or raw file playback).
    private struct ShapeFrame: ViewModifier {
        var contentAspect: CGFloat? = nil
        func body(content: Content) -> some View {
            if let contentAspect {
                content
                    .frame(maxWidth: .infinity)
                    .aspectRatio(contentAspect, contentMode: .fit)
            } else {
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var media: some View {
        switch source {
        case .youtube(let id):         YouTubePlayer(id: id, isActive: isActive)
        case .insta(let id, let kind): InstaLinkCard(id: id, kind: kind, poster: instaPoster, handle: instaHandle, issue: issue, focus: instaFocus, onFocusChange: onInstaFocusChange)
        case .rawFile:                 Color.black   // TODO wire up file playback
        }
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

    // 1a — the YouTube embed carries its own title/channel, so below it we show
    // the poster's byline + note (red rule) and the Comment / React / Re-circle
    // actions.
    private var paperPlate: some View {
        VStack(spacing: 0) {
            if let author {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xFF0000)).frame(width: 3)
                    HStack(spacing: 9) {
                        Avatar(user: author)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(author.username)
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Style.ink)
                            if let caption {
                                // The note is the post's first comment, so tapping
                                // it opens the thread (same as the Comment button).
                                Text(caption).font(.system(size: 10.5))
                                    .foregroundStyle(Color(hex: 0x9A958E)).lineLimit(1)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onComment?() }
                            }
                        }
                        Spacer(minLength: 0)
                        if let trailingAccessory { trailingAccessory }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.top, 18)
            }
        }
        // The actions used to sit here, which is why only YouTube cards had any.
        // They're in CardFooter now, rendered once for every card type.
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.paper)
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

    // Author identity: avatar + name + caption subtitle. Tint is .white over
    // media / the navy plate, Style.ink on the cream plates.
    private func authorChip(_ author: User, tint: Color) -> some View {
        HStack(spacing: 9) {
            Avatar(user: author, ring: tint.opacity(0.45))
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

// Instagram reels don't play inline (the official embed is poster-only) and IG's
// terms don't license re-hosting the video — so a reel becomes a native still:
// the cover frame we re-hosted at compose, the creator's @handle, and a tap that
// opens the reel. openURL on the https link opens the Instagram app when it's
// installed (universal link) and Safari otherwise.
private struct InstaLinkCard: View {
    let id: String
    let kind: InstagramContentType
    var poster: MediaRef?
    var handle: String?
    var issue: IssueViewModel?
    var focus: Double = 0.5
    /// Compose only: dragging reports a new crop focus. Its presence puts the
    /// card in edit mode — drag to reposition, and no tap-out.
    var onFocusChange: ((Double) -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @State private var posterURL: URL?

    private var editing: Bool { onFocusChange != nil }

    // /reel/ and /p/ resolve; the plural /reels/ maps onto reel.
    private var segment: String { kind == .post ? "p" : "reel" }
    private var linkURL: URL? { URL(string: "https://www.instagram.com/\(segment)/\(id)/") }

    var body: some View {
        ZStack {
            ReelPoster(url: posterURL, focus: focus, onFocusChange: onFocusChange)
            scrim.allowsHitTesting(false)
            if editing { repositionHint.allowsHitTesting(false) }
            else       { playButton.allowsHitTesting(false) }
            watchBadge.allowsHitTesting(false)
        }
        // Feed: the whole card taps out to the reel. Edit: the drag lives in
        // ReelPoster, so no tap-out here.
        .contentShape(Rectangle())
        .onTapGesture { if !editing, let linkURL { openURL(linkURL) } }
        .task { await resolvePoster() }
    }

    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.35), location: 0.0),
            .init(color: .clear,              location: 0.28),
            .init(color: .clear,              location: 0.62),
            .init(color: .black.opacity(0.7), location: 1.0),
        ], startPoint: .top, endPoint: .bottom)
    }

    private var playButton: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .padding(20)
            .background(.ultraThinMaterial, in: SwiftUI.Circle())
            .overlay(SwiftUI.Circle().stroke(.white.opacity(0.5), lineWidth: 1))
    }

    // Compose: a top pill telling the author the poster is draggable.
    private var repositionHint: some View {
        Label("Drag to reposition", systemImage: "arrow.up.and.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // Bottom-left: IG glyph + @handle over a "Watch on Instagram" line.
    private var watchBadge: some View {
        HStack(spacing: 9) {
            instaGlyph
            VStack(alignment: .leading, spacing: 1) {
                if let handle, !handle.isEmpty {
                    Text("@\(handle)").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }
                Text("Watch on Instagram")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    // A small rounded square in Instagram's gradient with a camera glyph — the
    // closest we get without shipping their logo.
    private var instaGlyph: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: [Color(hex: 0x515BD4), Color(hex: 0xE1306C), Color(hex: 0xFCAF45)],
                                 startPoint: .bottomLeading, endPoint: .topTrailing))
            .frame(width: 28, height: 28)
            .overlay(Image(systemName: "camera.fill").font(.system(size: 12)).foregroundStyle(.white))
    }

    private func resolvePoster() async {
        switch poster {
        case .direct(let url):    posterURL = url
        case .stored(let path):   posterURL = await issue?.signedURL(path: path)
        case nil:                 posterURL = nil
        }
    }
}

// The reel still, cropped to its container (a 9:16 image fills the width and
// overflows the shorter crop window). `focus` picks which vertical band shows —
// 0 top, 1 bottom, 0.5 centered. In edit mode a vertical drag reports a new
// focus so the author can reposition the crop at compose time.
private struct ReelPoster: View {
    let url: URL?
    var focus: Double = 0.5
    var onFocusChange: ((Double) -> Void)? = nil
    @State private var focusAtDragStart: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let wh = geo.size.height
            let imageH = w * 16.0 / 9.0                 // a reel is 9:16 at this width
            let overflow = max(imageH - wh, 0)          // hidden height above+below
            let clamped = min(max(focus, 0), 1)
            image(width: w, height: imageH)
                .offset(y: -overflow * clamped)          // 0 shows top, 1 shows bottom
                .frame(width: w, height: wh, alignment: .top)
                .clipped()
                .contentShape(Rectangle())
                .gesture(onFocusChange.map { dragGesture(overflow: overflow, report: $0) })
        }
    }

    @ViewBuilder
    private func image(width: CGFloat, height: CGFloat) -> some View {
        if let url {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { gradient }
                .frame(width: width, height: height)
        } else {
            gradient.frame(width: width, height: height)
        }
    }

    private var gradient: some View {
        LinearGradient(colors: [.purple, .pink, .orange],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Drag up reveals lower in the frame (focus →1); drag down reveals higher
    // (focus →0). Moving by the full overflow spans the whole range.
    private func dragGesture(overflow: CGFloat, report: @escaping (Double) -> Void) -> some Gesture {
        DragGesture()
            .onChanged { g in
                let base = focusAtDragStart ?? focus
                focusAtDragStart = base
                let span = overflow > 0 ? overflow : 1
                report(min(max(base - g.translation.height / span, 0), 1))
            }
            .onEnded { _ in focusAtDragStart = nil }
    }
}

#Preview("InstaCard") {
    VideoCard(source: .insta(id: "DZ30GywAbc7", kind: .reel), author: nil, caption: nil, title: nil,
              instaHandle: "infinite_mantra")
}
