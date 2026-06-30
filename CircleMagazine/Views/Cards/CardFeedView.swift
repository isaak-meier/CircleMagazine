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
                    ContributorsRow(contributors: magazine.contributors)
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
            let peek = Style.Space.xxl              // lip of the next card at the bottom
            let topGap = Style.Space.sm             // small space under the contributors row
            let cardHeight = geo.size.height - peek - topGap
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
            // viewAligned snaps to each card; asymmetric margins keep the first
            // card close under the contributors row while still peeking the next.
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .contentMargins(.top, topGap, for: .scrollContent)
            .contentMargins(.bottom, peek, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Contributors row

// The edition's authors, in a horizontal scroller below the masthead.
// ponytail: every author shown is an active contributor — the mockup's dashed
// "inactive friend" state needs a friends list we don't have yet; add it then.
private struct ContributorsRow: View {
    let contributors: [User]

    var body: some View {
        VStack(alignment: .leading, spacing: Style.Space.sm) {
            let contStr = contributors.count == 1 ? "CONTRIBUTOR" : "CONTRIBUTORS"
            Text("\(contributors.count) \(contStr)")
                .font(Style.eyebrow).tracking(1.0)
                .foregroundStyle(Style.meta)
            ScrollView(.horizontal) {
                HStack(spacing: Style.Space.md) {
                    ForEach(contributors, id: \.id) { ContributorBubble(user: $0) }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Style.Space.xl)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Style.rule).frame(height: 1) }
    }
}

private struct ContributorBubble: View {
    let user: User

    var body: some View {
        VStack(spacing: 5) {
            avatar
                .padding(2)                              // 2px edition ring around the avatar
                .background(Style.edition, in: SwiftUI.Circle())
            Text(user.username)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(hex: 0x4A4742))
                .lineLimit(1)
        }
    }

    private var avatar: some View {
        AsyncImage(url: user.avatarUrl.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() }
            placeholder: {
                Color(hex: 0x3A3A52).overlay(
                    Text(user.username.prefix(2).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white))
            }
            .frame(width: 32, height: 32)
            .clipShape(SwiftUI.Circle())
            .overlay(SwiftUI.Circle().stroke(Style.chrome, lineWidth: 2))
    }
}

#Preview {
    CardFeedView(issueLoader: .preview(.loaded(Magazine.sample)))
}
