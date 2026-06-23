//
//  RootTabView.swift
//  CircleMagazine
//
//  The signed-in root: owns the nav bar and the selected tab, swapping the
//  screen above a persistent bar. Tabs stay alive (ZStack + opacity) so the
//  feed keeps its scroll/load state across switches.
//

import SwiftUI

struct RootTabView: View {
    let issueLoader: IssueLoader
    let account: AccountManager
    @State private var tab: Tab = .feed

    enum Tab { case feed, account }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CardFeedView(issueLoader: issueLoader)
                    .opacity(tab == .feed ? 1 : 0).allowsHitTesting(tab == .feed)
                AccountView(account: account)
                    .opacity(tab == .account ? 1 : 0).allowsHitTesting(tab == .account)
            }
            navBar
        }
        .background(Style.chrome)
    }

    // MARK: Nav bar

    private var navBar: some View {
        HStack {
            Button { tab = .feed } label: { navIcon("house.fill", active: tab == .feed) }
            navIcon("magnifyingglass")
            compose
            navIcon("bell")
            Button { tab = .account } label: { navIcon("person", active: tab == .account) }
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
    RootTabView(issueLoader: .preview(.loaded(Magazine.sample)),
                account: AccountManager(db: DatabaseService()))
}
