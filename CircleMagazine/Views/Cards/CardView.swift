//
//  CardView.swift
//  CircleMagazine
//
//

import SwiftUI
import AVKit

struct CardView: View {
    let viewModel: CardViewModel
    /// Comments are interactive only when the feed passes the service + viewer.
    /// Nil in the compose preview, where the bar is a static mockup.
    var db: DatabaseService? = nil
    var me: User? = nil

    @State private var showComments = false

    private var commentsEnabled: Bool { db != nil && me != nil }

    var body: some View {
        VStack(spacing: 0) {
            content
            CommentBar(action: commentsEnabled ? { showComments = true } : nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Style.paper)
        .clipShape(RoundedRectangle(cornerRadius: Style.cardRadius))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
        .sheet(isPresented: $showComments) {
            if let db, let me {
                CommentsView(db: db, pageId: viewModel.id, me: me)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        // ponytail: .first — video-only cards; switch on the full array if mixed cards appear
        switch viewModel.media.first {
        case .video(let source): VideoCard(source: source, author: viewModel.author, caption: viewModel.caption, title: viewModel.title, captionStyle: viewModel.captionStyle, cardShape: viewModel.cardShape)
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

// MARK: - Comment bar

// The "Add a comment…" pill that closes every card (design 1a–1d). Sits below
// whatever content the card rendered, so image and video cards share it.
private struct CommentBar: View {
    /// Tap handler — nil renders a static (non-interactive) bar, e.g. in previews.
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { pill }.buttonStyle(.plain)
        } else {
            pill
        }
    }

    private var pill: some View {
        HStack(spacing: 11) {
            SwiftUI.Circle().fill(Style.rule)
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "person.fill")
                    .font(.system(size: 11)).foregroundStyle(Style.meta))
            Text("Add a comment…")
                .font(.system(size: 14)).foregroundStyle(Color(hex: 0xA8A39C))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Style.rule, lineWidth: 1))
        .padding(.horizontal, Style.Space.lg)
        .padding(.top, 14).padding(.bottom, Style.Space.lg)
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


#if DEBUG
#Preview("Card") {
    CardView(viewModel: CardViewModel(from: Magazine.sample.pages[0]))
        .frame(height: 600)
        .padding()
        .background(Style.chrome)
}
#endif
