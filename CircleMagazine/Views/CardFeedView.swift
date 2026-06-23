//
//  CardFeedView.swift
//  CircleMagazine
//
//  The signed-in root: editorial masthead, a peek-paged stack of cards (swipe
//  one at a time, the next peeking underneath), and a static nav bar.
//

import SwiftUI

struct CardFeedView: View {
    var cards: [Card] = Card.sample

    var body: some View {
        VStack(spacing: 0) {
            masthead
            viewport
            navBar
        }
        .background(Style.chrome)
    }

    // MARK: Masthead

    private var masthead: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Circle").font(Style.wordmark).foregroundStyle(Style.ink)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("THIS SUNDAY'S EDITION")
                    .font(.system(size: 8, weight: .semibold)).tracking(1.6)
                Text("JUNE 22, 2026")
                    .font(.system(size: 10.5, weight: .medium)).tracking(0.6)
            }
            .foregroundStyle(Style.edition)
        }
        .padding(.bottom, Style.Space.md)
        .overlay(alignment: .bottom) { Rectangle().fill(Style.ink).frame(height: 2) }
        .padding(.horizontal, Style.Space.lg)
        .padding(.top, Style.Space.sm)
    }

    // MARK: Peek-paged card viewport

    private var viewport: some View {
        GeometryReader { geo in
            let peek = Style.Space.xxl              // sliver of the neighbour cards
            let cardHeight = geo.size.height - peek * 2
            ScrollView(.vertical) {
                LazyVStack(spacing: Style.Space.sm) {
                    ForEach(cards) { card in
                        CardView(card: card)
                            .frame(height: cardHeight)
                            .padding(.horizontal, Style.Space.md)
                    }
                }
                .scrollTargetLayout()
            }
            // viewAligned snaps to each card; peek margin centers it (paging would
            // snap by viewport height and drift, since cards are < viewport tall).
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .contentMargins(.vertical, peek, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Nav bar

    private var navBar: some View {
        HStack {
            navIcon("house.fill", active: true)
            navIcon("magnifyingglass")
            compose
            navIcon("bell")
            navIcon("person")
        }
        .padding(.horizontal, Style.Space.xl)
        .padding(.top, Style.Space.sm)
        .padding(.bottom, Style.Space.xl)
        .background(Style.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Style.rule).frame(height: 1) }
    }

    private func navIcon(_ symbol: String, active: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 21))
            .foregroundStyle(active ? Style.ink : Style.meta)
            .frame(maxWidth: .infinity)
    }

    private var compose: some View {
        Image(systemName: "plus")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Style.paper)
            .frame(width: 44, height: 44)
            .background(SwiftUI.Circle().fill(Style.ink))
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    CardFeedView()
}
