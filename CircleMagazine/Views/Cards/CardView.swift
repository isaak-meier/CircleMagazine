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
        VStack(alignment: .leading, spacing: 0) {
            handle
            CardMediaRegion(card: viewModel)
                .padding(.horizontal, Style.Space.lg)
            Spacer(minLength: 0)
        }
        .background(Style.paper)
        .clipShape(RoundedRectangle(cornerRadius: Style.cardRadius))
        .shadow(color: .black.opacity(0.13), radius: 16, y: 4)
    }

    private var handle: some View {
        Capsule().fill(Style.rule)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10).padding(.bottom, 6)
    }
}

// MARK: - Media region (one per template)

private struct CardMediaRegion: View {
    let card: CardViewModel

    var body: some View {
        switch cardTemplate(for: card.media) {
        case .photo, .fallback: PhotoMedia(url: url(.image))
        case .video:            VideoMedia()
        case .photoAudio:       PhotoAudioMedia(url: url(.image), audioURL: url(.audio))
        case .photoText:
            VStack(spacing: Style.Space.md) {
                PhotoMedia(url: url(.image))
                textBlock
            }
        case .photoAudioText:
            VStack(spacing: Style.Space.md) {
                PhotoAudioMedia(url: url(.image), audioURL: url(.audio))
                textBlock
            }
        case .pullquote:        PullQuoteMedia(text: quote)
        }
    }

    /// All text widgets, in position order, stacked below the image.
    private var textBlock: some View {
        Text(allText)
            .font(Style.body).foregroundStyle(Style.ink.opacity(0.78))
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allText: String {
        card.media.filter { $0.widgetType == .text }
            .compactMap(\.textContent).joined(separator: "\n\n")
    }

    private var quote: String { card.media.first { $0.widgetType == .text }?.textContent ?? "" }
    private func url(_ type: WidgetType) -> URL? {
        card.media.first { $0.widgetType == type }?.mediaUrl.flatMap(URL.init(string:))
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

private struct VideoMedia: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0F2027), Color(hex: 0x203A43), Color(hex: 0x2C5364)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "play.fill")
                .font(.system(size: 18)).foregroundStyle(Style.ink)
                .padding(17).background(SwiftUI.Circle().fill(.white.opacity(0.93)))
            VStack {
                HStack {
                    tag("VIDEO", bg: .black.opacity(0.38)); Spacer()
                }
                Spacer()
                HStack { Spacer(); tag("1:24", bg: .black.opacity(0.5)) }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity).frame(height: mediaHeight)
        .clipShape(RoundedRectangle(cornerRadius: Style.mediaRadius))
    }
    private func tag(_ s: String, bg: Color) -> some View {
        Text(s).font(.system(size: 9.5, weight: .semibold)).tracking(0.8)
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(bg))
    }
}

private struct PhotoAudioMedia: View {
    let url: URL?
    let audioURL: URL?
    @State private var player: AVPlayer?
    @State private var playing = false

    var body: some View {
        ZStack {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(Style.rule) }
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
            Button(action: toggle) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 16)).foregroundStyle(Style.ink)
                    .padding(15).background(SwiftUI.Circle().fill(.white.opacity(0.93)))
            }
            VStack {
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "music.note").font(.system(size: 10))
                    Text("Now playing").font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.white).padding(12)
            }
        }
        .frame(maxWidth: .infinity).frame(height: mediaHeight)
        .clipShape(RoundedRectangle(cornerRadius: Style.mediaRadius))
        .onDisappear { player?.pause() }
    }

    private func toggle() {
        if player == nil, let audioURL { player = AVPlayer(url: audioURL) }
        playing ? player?.pause() : player?.play()
        playing.toggle()
    }
}

private struct PullQuoteMedia: View {
    let text: String
    var body: some View {
        HStack {
            Text("“\(text)”").font(Style.pullQuote).italic()
                .foregroundStyle(Color(hex: 0x2A2826)).lineSpacing(5)
            Spacer(minLength: 0)
        }
        .padding(Style.Space.lg)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(Color.black.opacity(0.025))
        .overlay(alignment: .leading) { Rectangle().fill(Style.ink).frame(width: 2.5) }
        .clipShape(RoundedRectangle(cornerRadius: Style.mediaRadius))
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
