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
            case .video(let source): VideoCard(source)
            case .image(let url): standardCard()
            case .fallback(let error): standardCard()
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

// Full-bleed video card: video fills the whole card, author pinned to the bottom.
private struct VideoCard: View {

    var body: some View {
        ZStack {
            Image(systemName: "play.fill")
                .font(.system(size: 22)).foregroundStyle(Style.ink)
                .padding(20).background(SwiftUI.Circle().fill(.white.opacity(0.93)))
            VStack(spacing: 0) {
                handle
                Spacer(minLength: 0)
                author
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var handle: some View {
        Capsule().fill(.white.opacity(0.6))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
    }

    // ponytail: hardcoded per request — swap for viewModel.author once the bio field exists.
    private var author: some View {
        HStack(alignment: .top, spacing: 9) {
            SwiftUI.Circle().fill(.white.opacity(0.22))
                .frame(width: 36, height: 36)
                .overlay(Text("P").font(Style.byline).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text("Philly Bum Bum").font(Style.byline).foregroundStyle(.white)
                Text("Bum about town. Hoagie purist. I film the city while it sleeps.")
                    .font(Style.body).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Style.Space.lg)
        .padding(.top, Style.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.78)],
                                   startPoint: .top, endPoint: .bottom))
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
