//
//  CardView.swift
//  CircleMagazine
//
//

import SwiftUI
import AVKit

struct CardView: View {
    let viewModel: CardViewModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Style.paper)
            .clipShape(RoundedRectangle(cornerRadius: Style.cardRadius))
            .shadow(color: .black.opacity(0.13), radius: 16, y: 4)
    }

    @ViewBuilder
    private var content: some View {
        // ponytail: .first — video-only cards; switch on the full array if mixed cards appear
        switch viewModel.media.first {
        case .video(let source): VideoCard(source: source, author: viewModel.author, caption: viewModel.caption, title: viewModel.title)
        default:                 standardCard   // image / fallback / empty
        }
    }

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle
            if let author = viewModel.author {
                AuthorRow(author: author)
                    .padding(.horizontal, Style.Space.lg)
                    .padding(.bottom, Style.Space.md)
            }
            CardMediaRegion(card: viewModel)
                .padding(.horizontal, Style.Space.lg)
            Spacer(minLength: 0)
        }
    }

    private var handle: some View {
        Capsule().fill(Style.rule)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10).padding(.bottom, 6)
    }
}

// MARK: - Author row

private struct AuthorRow: View {
    let author: User

    var body: some View {
        HStack(spacing: 9) {
            avatar
            Text(author.username).font(Style.byline).foregroundStyle(Style.ink)
        }
    }

    private var avatar: some View {
        AsyncImage(url: author.avatarUrl.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() }
            placeholder: {
                Style.rule.overlay(
                    Text(author.username.prefix(1)).font(Style.byline)
                        .foregroundStyle(Style.meta))
            }
            .frame(width: 32, height: 32).clipShape(SwiftUI.Circle())
    }
}

// MARK: - Media region

private struct CardMediaRegion: View {
    let card: CardViewModel

    @ViewBuilder
    var body: some View {
        if case .image(let url) = card.media.first {
            PhotoMedia(url: url)
        }
    }
}

private let mediaHeight: CGFloat = 220

private struct PhotoMedia: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(Style.rule) }
            .frame(maxWidth: .infinity).frame(height: mediaHeight)
            .clipShape(RoundedRectangle(cornerRadius: Style.mediaRadius))
    }
}

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
                if let url = URL(string: "https://www.youtube.com/watch?v=\(id)") { openURL(url) }
            }
    }
}

#if DEBUG
#Preview("Card") {
    CardView(viewModel: CardViewModel(from: Magazine.sample.pages[0]))
        .frame(height: 600)
        .padding()
        .background(Style.chrome)
}
#endif
