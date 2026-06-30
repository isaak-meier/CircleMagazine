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
    @State private var composing = false

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
        .sheet(isPresented: $composing) { composeSheet }
    }

    // Compose needs the signed-in author and the live issue id; both come from
    // state this view already owns. Posting refreshes the feed so it shows up.
    // RootTabView only renders when signed in, so .loading/.signedOut are
    // defensive — but the sheet handles them rather than coming up blank.
    @ViewBuilder
    private var composeSheet: some View {
        switch account.authState {
        case .signedIn(let user):
            ComposeView(db: issueLoader.db, issueId: liveIssueId, author: user) {
                tab = .feed
                await issueLoader.refresh()
            }
        case .loading:
            composeFallback("One moment — loading your account…", loading: true)
        case .signedOut:
            composeFallback("Sign in to share a video.")
        }
    }

    private func composeFallback(_ message: String, loading: Bool = false) -> some View {
        VStack(spacing: Style.Space.lg) {
            Capsule().fill(Style.rule).frame(width: 36, height: 4).padding(.top, 10)
            Spacer()
            if loading { ProgressView() }
            Text(message)
                .font(Style.body).foregroundStyle(Style.meta)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Close") { composing = false }
                .font(Style.button).foregroundStyle(Style.ink)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Style.paper)
        .presentationDetents([.medium])
    }

    private var liveIssueId: UUID? {
        guard case .loaded(let magazine) = issueLoader.loadState else { return nil }
        return magazine.issue.id
    }

    // MARK: Nav bar

    private var navBar: some View {
        HStack {
            Button { tab = .feed } label: { navIcon("house.fill", active: tab == .feed) }
            navIcon("magnifyingglass")
            Button { composing = true } label: { compose }
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
