//
//  CardFeedView.swift
//  CircleMagazine
//
//  The feed screen: editorial masthead over a peek-paged stack of cards (swipe
//  one at a time, the next peeking underneath). Hosted by RootTabView, which
//  owns the nav bar.
//

import SwiftUI

struct CardFeedView: View {
    let vm: IssueViewModel
    /// The signed-in viewer, so cards can open the comments sheet. Nil in
    /// previews / signed-out, where comment bars stay static.
    var me: User? = nil
    /// Masthead wordmark + optional flanking controls (back / members / compose),
    /// supplied by the circle screen; defaults keep the standalone feed unchanged.
    var title: String = "Circle"
    var mastheadLeading: AnyView? = nil
    var mastheadTrailing: AnyView? = nil
    /// The card the feed is snapped to (its page id), for YouTube autoplay.
    @State private var visibleCardId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Masthead(title: title, stamp: editionDate,
                     leading: mastheadLeading, trailing: mastheadTrailing)
            switch vm.state {
                case .loading:
                    Spacer()
                    Text("Retrieving latest issue...")
                    ProgressView()
                    Spacer()
                case .loaded(let magazine) where magazine.cards.isEmpty:
                    emptyEdition
                case .loaded(let magazine):
                    viewport(for: magazine)
                // The circle screen routes the compose phase to the chat before
                // it gets here; this is the standalone-feed fallback.
                case .composing:
                    emptyEdition
                case .failedToLoad(let errorStr):
                    Spacer()
                    VStack(spacing: Style.Space.md) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundStyle(Style.meta)
                        Text("Hmm.. I didn't expect that.")
                            .font(Style.cardTitle)
                            .foregroundStyle(Style.ink)
                        Text("Try again in a little while.")
                            .font(Style.body)
                            .foregroundStyle(Style.meta)
                        Text(errorStr)
                            .font(Style.stamp)
                            .foregroundStyle(Style.meta.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Style.Space.xl)
                    Spacer()
            }
        }
        .background(Style.chrome)
        .task { await vm.appear() }
    }

    // A live-or-draft edition that exists but has no posts yet. Distinct from
    // the failure state — nothing went wrong, it's just waiting to be filled.
    private var emptyEdition: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Style.Space.md) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 32))
                    .foregroundStyle(Style.meta)
                Text("Nothing here yet.")
                    .font(Style.cardTitle)
                    .foregroundStyle(Style.ink)
                Text("This edition is still being written. Tap ＋ to add the first piece.")
                    .font(Style.body)
                    .foregroundStyle(Style.meta)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Style.Space.xl)
            Spacer()
        }
    }

    // The live issue's date once loaded; nil (no stamp) while loading/failed.
    private var editionDate: String? {
        guard case .loaded(let magazine) = vm.state else { return nil }
        return magazine.issue.editionDate
    }

    // MARK: Peek-paged card viewport

    private func viewport(for magazine: Magazine) -> some View {
        let peek = Style.Space.xxl              // lip of the next card at the bottom
        let topGap = Style.Space.sm             // small space under the contributors row
        // Nil until the first scroll — treat the top card as active so it
        // autoplays on open.
        let activeId = visibleCardId ?? magazine.cards.first?.id
        return ScrollView(.vertical) {
            LazyVStack(spacing: Style.Space.sm) {
                ForEach(magazine.cards) { cardViewModel in
                    let card = CardView(viewModel: cardViewModel, issue: vm, me: me,
                                        isActive: cardViewModel.id == activeId,
                                        onDelete: { await vm.delete(pageId: cardViewModel.id) })
                    // A reel card sizes to its cropped poster; every other card
                    // fills the viewport height.
                    if cardViewModel.isTallInsta {
                        card.feedCardWidth()
                    } else {
                        card.feedCardFrame()
                    }
                }
            }
            .scrollTargetLayout()
        }
        // viewAligned snaps to each card; asymmetric margins keep the first
        // card close under the contributors row while still peeking the next.
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $visibleCardId)
        .contentMargins(.top, topGap, for: .scrollContent)
        .contentMargins(.bottom, peek, for: .scrollContent)
        .scrollIndicators(.hidden)
    }
}


#Preview {
    CardFeedView(vm: .preview(.loaded(Magazine.sample)))
}
