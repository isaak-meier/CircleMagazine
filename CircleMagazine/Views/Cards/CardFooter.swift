//
//  CardFooter.swift
//  CircleMagazine
//
//  The row under every card: who reacted, and the two things you can do about a
//  post. It used to live inside the YouTube card's caption plate, which meant
//  photo cards and link cards had no actions at all — so it moved up to
//  `CardView`, the one place all three card types funnel through.
//
//  No counts anywhere. The faces are the count: reactions are felt, not tallied,
//  which is the whole reason a reaction is a photo of you rather than a tap.
//

import SwiftUI

struct CardFooter: View {
    let card: CardViewModel
    /// True while this card's reaction photo is uploading.
    var isReacting: Bool = false
    let onComment: () -> Void
    /// Take (or retake) a reaction photo — the caller owns camera vs library.
    let onReact: () -> Void
    let onRemoveReaction: () -> Void
    /// Opens the reactors' photos.
    let onOpenReactions: () -> Void

    // How many faces before the row starts eating the buttons.
    private let maxFaces = 5

    var body: some View {
        HStack(spacing: Style.Space.sm) {
            pill("Comment", systemImage: "bubble.left", filled: false, action: onComment)
            reactControl
            // Trailing, and it takes whatever's left: the two actions hug their
            // labels (stretched, they left no room for the faces and pushed the
            // cluster off the card's edge) and the cluster fills the rest.
            if !card.reactions.isEmpty { clusterPill }
        }
        .padding(Style.Space.lg)
    }

    // MARK: Cluster

    // Bare overlapping faces don't read as a control, so the cluster wears the
    // same pill as the buttons beside it, chevron included.
    private var clusterPill: some View {
        Button(action: onOpenReactions) {
            // Sized by its faces: one reaction is a pill wide enough for one
            // avatar and the chevron, and it grows a face at a time from there.
            // The two action pills take the rest.
            HStack(spacing: Style.Space.sm) {
                faces
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Style.meta)
            }
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(pillBackground(filled: false))
        }
        .buttonStyle(.plain)
        // The faces are decoration; the summary is the label. A Button already
        // merges its children, and wrapping it in `accessibilityElement` here
        // swallowed both the label and the identifier — the cluster came back as
        // "IT" with no identifier at all.
        .accessibilityLabel(card.reactionSummary ?? "Reactions")
        .accessibilityHint("Opens their photos")
        .accessibilityIdentifier("reactionCluster")
    }

    private var faces: some View {
        let shown = card.reactions.compactMap(\.author).prefix(maxFaces)
        let extra = card.reactions.count - shown.count
        return HStack(spacing: -9) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, user in
                Avatar(user: user, diameter: 24, ring: .white)
                    .zIndex(Double(maxFaces - index))   // first face on top
            }
            if extra > 0 { overflowFace }
        }
    }

    // Past five, a dotted face — never a number.
    private var overflowFace: some View {
        SwiftUI.Circle().fill(Style.rule)
            .frame(width: 24, height: 24)
            .overlay(Image(systemName: "ellipsis")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(Style.meta))
            .overlay(SwiftUI.Circle().stroke(.white, lineWidth: 2))
    }

    // MARK: React

    // Once you've reacted the button becomes a menu — a long press would be
    // invisible to VoiceOver and to UI automation, which this codebase has been
    // bitten by twice.
    @ViewBuilder
    private var reactControl: some View {
        if card.myReaction != nil {
            Menu {
                Button("Retake photo", systemImage: "camera", action: onReact)
                Button("Remove reaction", systemImage: "trash",
                       role: .destructive, action: onRemoveReaction)
            } label: {
                pillLabel("Reacted", systemImage: "checkmark", filled: true,
                          working: isReacting)
            }
            .accessibilityIdentifier("reactButton")
            .frame(maxWidth: .infinity)
        } else {
            pill("React", systemImage: "camera", filled: false,
                 working: isReacting, action: onReact)
                .accessibilityIdentifier("reactButton")
        }
    }

    // MARK: Pills

    private func pill(_ title: String, systemImage: String, filled: Bool,
                      working: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            pillLabel(title, systemImage: systemImage, filled: filled, working: working)
        }
        .buttonStyle(.plain)
    }

    private func pillLabel(_ title: String, systemImage: String, filled: Bool,
                           working: Bool = false) -> some View {
        HStack(spacing: 7) {
            if working {
                ProgressView().controlSize(.mini)
                    .tint(filled ? Style.paper : Style.ink)
            } else {
                Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
            }
            Text(title).font(.system(size: 12.5, weight: .semibold))
                // The cluster beside these is greedy; without this, "Comment"
                // wraps to two lines to give it room.
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(filled ? Style.paper : Style.ink)
        // Both actions split whatever the cluster leaves, so they're the same
        // width as each other on every card — the two things you can do don't
        // change size because someone reacted.
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(pillBackground(filled: filled))
    }

    @ViewBuilder
    private func pillBackground(filled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        if filled { shape.fill(Style.ink) }
        else { shape.fill(.white).overlay(shape.stroke(Style.rule, lineWidth: 1)) }
    }
}

#if DEBUG
/// Every state the row has, since the cluster changes the layout of the two pills
/// beside it and only the empty case is reachable from `Magazine.sample`.
#Preview("Footer") {
    let sample = Magazine.sample.pages[0]
    let me = previewUser("isaak the creator")
    let names = ["Dave Slater", "kebaybay", "Arnell", "Philly Bum Bum",
                 "jmoney", "Theo", "Nadia"]

    /// The sample page with `count` reactions on it, the first one the viewer's
    /// own when `mine` — that's what flips React into the Reacted menu.
    func card(_ count: Int, mine: Bool = false) -> CardViewModel {
        let reactors = (mine ? [me] : []) + names.prefix(count - (mine ? 1 : 0)).map(previewUser)
        return CardViewModel(
            from: MagazinePage(page: sample.page, pageMedia: sample.pageMedia,
                               author: sample.author,
                               reactions: reactors.map(previewReaction(by:))),
            meId: me.id)
    }

    return ScrollView {
        VStack(spacing: Style.Space.xl) {
            labelled("No reactions — the pills split the row") {
                CardFooter(card: CardViewModel(from: sample), onComment: {}, onReact: {},
                           onRemoveReaction: {}, onOpenReactions: {})
            }
            labelled("One, someone else's") {
                CardFooter(card: card(1), onComment: {}, onReact: {},
                           onRemoveReaction: {}, onOpenReactions: {})
            }
            labelled("Two, one of them yours — React becomes the menu") {
                CardFooter(card: card(2, mine: true), onComment: {}, onReact: {},
                           onRemoveReaction: {}, onOpenReactions: {})
            }
            labelled("Five — the cap, no overflow face yet") {
                CardFooter(card: card(5), onComment: {}, onReact: {},
                           onRemoveReaction: {}, onOpenReactions: {})
            }
            labelled("Seven — the ··· face, never a number") {
                CardFooter(card: card(7), onComment: {}, onReact: {},
                           onRemoveReaction: {}, onOpenReactions: {})
            }
            labelled("Uploading") {
                CardFooter(card: card(2, mine: true), isReacting: true, onComment: {},
                           onReact: {}, onRemoveReaction: {}, onOpenReactions: {})
            }
        }
        .padding(.vertical, Style.Space.xl)
    }
    .background(Style.chrome)
}

@ViewBuilder
private func labelled(_ note: String, @ViewBuilder row: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: Style.Space.xs) {
        Text(note.uppercased()).font(Style.eyebrow).tracking(1.2)
            .foregroundStyle(Style.meta)
            .padding(.horizontal, Style.Space.lg)
        row().background(Style.paper)
    }
}

private func previewUser(_ name: String) -> User {
    User(id: UUID(), username: name, bio: nil, avatarUrl: nil, role: nil,
         followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
}

/// The photo path never resolves in a preview — nothing signs it — but the
/// cluster only draws faces, so it doesn't need to.
private func previewReaction(by user: User) -> ReactionWithAuthor {
    ReactionWithAuthor(
        reaction: Reaction(id: UUID(), pageId: UUID(), userId: user.id,
                           mediaPath: "preview/reaction.jpg", createdAt: nil),
        author: user)
}
#endif
