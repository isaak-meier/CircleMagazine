//
//  LinkCard.swift
//  CircleMagazine
//
//  A shared link with no player of its own — an article, a shop, a recipe. The
//  cover image sits above a headline and the site it came from, and tapping the
//  card opens the link.
//
//  Everything it renders is decided by LinkPreview, so this file only does
//  layout: the title is never empty and the host is never missing by the time
//  they arrive here.
//

import SwiftUI

struct LinkCard: View {
    let preview: LinkPreview
    let author: User?
    let caption: String?
    /// Supplies signed URLs for a re-hosted cover. Nil in the compose preview,
    /// where the image is still the scraped URL.
    var issue: IssueViewModel? = nil
    /// The ⋯ menu, when the viewer owns the post.
    var trailingAccessory: AnyView? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle
            if preview.image != nil { cover }
            headline
            if let author { byline(author) }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { openURL(preview.destination) }
    }

    private var handle: some View {
        Capsule().fill(Style.rule)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10).padding(.bottom, 6)
    }

    /// 1.91:1 — the ratio Open Graph images are authored for, so a cover fills
    /// this without the crop eating anyone's title text.
    private var cover: some View {
        LinkImage(ref: preview.image, issue: issue)
            .aspectRatio(1.91, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: Style.Space.sm) {
                Text(preview.title)
                    .font(Style.cardTitle)
                    .foregroundStyle(Style.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Spacer(minLength: 0)
                if let trailingAccessory { trailingAccessory }
            }
            // The provenance line: the one thing a reader wants before tapping
            // out of the app. Dropped when the title already IS the host — a
            // page with no metadata would otherwise say its domain twice.
            if preview.title != preview.host {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .semibold))
                    Text(preview.host)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(Style.meta)
            }

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(Style.body).foregroundStyle(Style.ink)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, Style.Space.lg)
        .padding(.top, Style.Space.md)
    }

    private func byline(_ author: User) -> some View {
        HStack(spacing: Style.Space.sm) {
            Avatar(user: author, diameter: 22)
            Text(author.username)
                .font(Style.byline).foregroundStyle(Style.meta)
        }
        .padding(.horizontal, Style.Space.lg)
        .padding(.top, Style.Space.md)
        .padding(.bottom, Style.Space.md)
    }
}

/// The cover image. A stored path is signed on appear (the bucket is private and
/// signatures expire); a scraped URL loads directly. Nothing is rendered when
/// there's no image — the card is designed to stand without one.
private struct LinkImage: View {
    let ref: MediaRef?
    var issue: IssueViewModel?

    @State private var url: URL?

    var body: some View {
        Color.clear
            // Top-anchored: og:image is *specced* as 1.91:1 but plenty of sites
            // publish a portrait poster or book cover, and a centred crop of one
            // of those lands on the middle of nothing.
            .overlay(alignment: .top) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() }
                    placeholder: { Rectangle().fill(Style.rule) }
            }
            .clipped()
            .task(id: ref?.id ?? "") { url = await ref?.resolve(with: issue) }
    }
}

#if DEBUG
#Preview("Link card") {
    let author = User(id: UUID(), username: "Philly Bum Bum", bio: nil, avatarUrl: nil,
                      role: nil, followCredits: nil, circleSlots: nil, isVerified: nil,
                      createdAt: nil)
    return VStack(spacing: 16) {
        LinkCard(preview: LinkPreview(destination: URL(string: "https://www.theatlantic.com/x")!,
                                      title: "The Quietest Place in America",
                                      image: nil),
                 author: author, caption: "had to share this one")
        .background(Style.paper, in: RoundedRectangle(cornerRadius: Style.cardRadius))

        // No metadata at all — named by its host, still a card.
        LinkCard(preview: LinkPreview(destination: URL(string: "https://example.com/a")!,
                                      meta: nil),
                 author: author, caption: nil)
        .background(Style.paper, in: RoundedRectangle(cornerRadius: Style.cardRadius))
    }
    .padding()
    .background(Style.chrome)
}
#endif
