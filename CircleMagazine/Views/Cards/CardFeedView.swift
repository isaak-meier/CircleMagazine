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
    let issueLoader: IssueLoader

    var body: some View {
        VStack(spacing: 0) {
            Masthead(title: "Circle", editionDate: editionDate)
            switch issueLoader.loadState {
                case .loading:
                    Spacer()
                    Text("Retrieving latest issue...")
                    ProgressView()
                    Spacer()
                case .loaded(let magazine):
                    viewport(for: magazine)
                case .failedToLoad(let errorStr):
                    Text(errorStr)
            }
        }
        .background(Style.chrome)
        .task { await issueLoader.refreshIfNeeded() }
    }

    // The live issue's date once loaded; nil (no stamp) while loading/failed.
    private var editionDate: String? {
        guard case .loaded(let magazine) = issueLoader.loadState else { return nil }
        return magazine.issue.editionDate
    }

    // MARK: Peek-paged card viewport

    private func viewport(for magazine: Magazine) -> some View {
        GeometryReader { geo in
            let peek = Style.Space.xxl              // sliver of the neighbour cards
            let cardHeight = geo.size.height - peek * 2
            ScrollView(.vertical) {
                LazyVStack(spacing: Style.Space.sm) {
                    ForEach(magazine.cards) { cardViewModel in
                        CardView(viewModel: cardViewModel)
                            .frame(height: cardHeight)
                            .padding(.horizontal, Style.Space.md)
                    }
                }
                .scrollTargetLayout()
            }
            // viewAligned snaps to each card;
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .contentMargins(.vertical, peek, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }
}

#Preview {
    CardFeedView(issueLoader: .preview(.loaded(Magazine.sample)))
}
