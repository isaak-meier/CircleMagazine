//
//  WidgetView.swift
//  CircleMagazine
//
//  Renders a single widget by type and zooms it fullscreen on tap.
//

import SwiftUI
import AVKit

struct WidgetView: View {
    let media: PageMedia
    var namespace: Namespace.ID
    @State private var zoomed = false

    var body: some View {
        if let content = media.widgetContent {
            tile(content: content)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture { zoomed = true }
                .fullScreenCover(isPresented: $zoomed) {
                    cover(content: content)
                }
        } else {
            // ponytail: malformed widget row (missing url/text) — show a neutral tile.
            RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.2))
        }
    }

    // ponytail: zoom transition is iOS 18+; gate it so the app still builds/runs
    // on the 17.6 deployment target with a plain cross-dissolve fallback.
    @ViewBuilder
    private func tile(content: WidgetContent) -> some View {
        let body = WidgetBody(content: content, fullscreen: false)
        if #available(iOS 18.0, *) {
            body.matchedTransitionSource(id: media.id, in: namespace)
        } else {
            body
        }
    }

    @ViewBuilder
    private func cover(content: WidgetContent) -> some View {
        let body = ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            WidgetBody(content: content, fullscreen: true)
            Button { zoomed = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white, .black.opacity(0.4))
                    .padding()
            }
        }
        if #available(iOS 18.0, *) {
            body.navigationTransition(.zoom(sourceID: media.id, in: namespace))
        } else {
            body
        }
    }
}

private struct WidgetBody: View {
    let content: WidgetContent
    let fullscreen: Bool

    var body: some View {
        switch content {
        case .text(let string):
            Text(string)
                .font(fullscreen ? .title2 : .subheadline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(fullscreen ? 24 : 12)
                .background(.thinMaterial)
        case .image(let url):
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: fullscreen ? .fit : .fill)
            } placeholder: {
                Color.gray.opacity(0.15)
            }
        case .video(let url):
            VideoWidget(url: url)
        case .audio(let url):
            AudioWidget(url: url, fullscreen: fullscreen)
        }
    }
}

/// Holds the player in state so scrolling/re-render doesn't restart playback.
private struct VideoWidget: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .background(.black)
            .onAppear { if player == nil { player = AVPlayer(url: url) } }
            .onDisappear { player?.pause() }
    }
}

private struct AudioWidget: View {
    let url: URL
    let fullscreen: Bool
    @State private var player: AVPlayer?
    @State private var playing = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            Button(action: toggle) {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                    .resizable().scaledToFit()
                    .frame(width: fullscreen ? 88 : 32)
                    .foregroundStyle(.white)
            }
        }
        .onDisappear { player?.pause() }
    }

    private func toggle() {
        if player == nil { player = AVPlayer(url: url) }
        playing ? player?.pause() : player?.play()
        playing.toggle()
    }
}
