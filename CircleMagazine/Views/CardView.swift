//
//  CardView.swift
//  CircleMagazine
//
//  One card: a fixed-size shell (handle · author · media · title/excerpt · tags)
//  whose media region switches on the page's media combination (cardTemplate).
//

import SwiftUI
import AVKit

struct CardView: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle
            author
            CardMediaRegion(card: card)
                .padding(.horizontal, Style.Space.lg)
            cardBody
            Spacer(minLength: 0)
            footer
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

    private var author: some View {
        HStack(spacing: 9) {
            Text(card.authorAvatar)
                .font(.system(size: 15))
                .frame(width: 32, height: 32)
                .background(SwiftUI.Circle().fill(Style.rule))
            VStack(alignment: .leading, spacing: 1) {
                Text(card.authorName).font(.system(size: 13, weight: .semibold)).foregroundStyle(Style.ink)
                Text(card.timeText).font(.system(size: 10.5)).foregroundStyle(Style.meta)
            }
            Spacer()
        }
        .padding(.horizontal, Style.Space.lg)
        .padding(.bottom, Style.Space.md)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(card.title)
                .font(Style.cardTitle).foregroundStyle(Style.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.excerpt)
                .font(.system(size: 13)).foregroundStyle(Style.ink.opacity(0.78))
                .lineLimit(2).lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Style.Space.lg)
        .padding(.top, Style.Space.md)
    }

    private var footer: some View {
        HStack(spacing: Style.Space.sm) {
            ForEach(card.tags, id: \.self) { tag in
                Text(tag.uppercased())
                    .font(.system(size: 9.5, weight: .medium)).tracking(0.6)
                    .foregroundStyle(Style.meta)
                    .padding(.horizontal, Style.Space.sm).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Style.rule))
            }
            Spacer()
        }
        .padding(.horizontal, Style.Space.lg)
        .padding(.vertical, Style.Space.md)
    }
}

// MARK: - Media region (one per template)

private struct CardMediaRegion: View {
    let card: Card

    var body: some View {
        switch cardTemplate(for: card.media) {
        case .photo, .fallback: PhotoMedia(url: url(.image))
        case .video:            VideoMedia()
        case .photoAudio:       PhotoAudioMedia(url: url(.image), audioURL: url(.audio))
        case .pullquote:        PullQuoteMedia(text: quote)
        }
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
    CardView(card: Card.sample[0])
        .frame(height: 600)
        .padding()
        .background(Style.chrome)
}
#endif
