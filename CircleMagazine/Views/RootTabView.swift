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

    /// A circle being entered from the Circles tab: the circle screen sits
    /// beneath the tab UI while the splash-style ripple reveals it from the
    /// tap point. Currently the members roster — chat is parked for later.
    struct EnteredCircle {
        let summary: CircleSummary
        let tone: CircleBubbleLayout.BubbleTone
        let origin: CGPoint
    }
    @State private var entered: EnteredCircle?
    @State private var chatRevealed = false
    /// The notifications placeholder's gag: true after the bait is taken.
    @State private var eyebrowsRaised = false
    /// Invite code from a circlemagazine://join?code=… deep link, handed to the
    /// Circles tab which opens its join sheet prefilled.
    @State private var pendingJoinCode: String?

    enum Tab { case feed, circles, notifications, account }

    var body: some View {
        ZStack {
            if let entered, case .signedIn(let user) = account.authState {
                CircleMembersView(db: issueLoader.db, summary: entered.summary,
                                  tone: entered.tone, me: user) {
                    self.entered = nil
                    chatRevealed = false
                }
            }
            // Kept in the hierarchy (hidden, not removed) so tab state like
            // the feed's scroll position survives a trip into a chat.
            tabsAndNavBar
                .opacity(chatRevealed ? 0 : 1)
                .allowsHitTesting(!chatRevealed)
                // wave: false — the feed's webviews beneath can't take the
                // Metal shader (they'd render as red boxes); hole-mask only.
                .rippleReveal(origin: entered?.origin, wave: false) { chatRevealed = true }
        }
        .coordinateSpace(name: "root")
        .sheet(isPresented: $composing) { composeSheet }
        // ponytail: URLs are dropped if this view isn't up yet (app cold-starts
        // signed out) — stash the code at App level if that ever matters.
        .onOpenURL { url in
            guard url.scheme == "circlemagazine", url.host() == "join",
                  let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "code" })?.value
            else { return }
            entered = nil
            chatRevealed = false
            tab = .circles
            pendingJoinCode = code
        }
    }

    private var tabsAndNavBar: some View {
        VStack(spacing: 0) {
            ZStack {
                CardFeedView(issueLoader: issueLoader, me: signedInUser)
                    .opacity(tab == .feed ? 1 : 0).allowsHitTesting(tab == .feed)
                CirclesView(db: issueLoader.db, account: account,
                            active: tab == .circles && entered == nil,
                            joinCode: $pendingJoinCode) { summary, tone, origin in
                    entered = EnteredCircle(summary: summary, tone: tone, origin: origin)
                }
                    .opacity(tab == .circles ? 1 : 0).allowsHitTesting(tab == .circles)
                notificationsPlaceholder
                    .opacity(tab == .notifications ? 1 : 0).allowsHitTesting(tab == .notifications)
                AccountView(account: account, issueLoader: issueLoader)
                    .opacity(tab == .account ? 1 : 0).allowsHitTesting(tab == .account)
            }
            navBar
        }
        .background(Style.chrome)
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

    private var signedInUser: User? {
        if case .signedIn(let user) = account.authState { return user }
        return nil
    }

    private var liveIssueId: UUID? {
        guard case .loaded(let magazine) = issueLoader.loadState else { return nil }
        return magazine.issue.id
    }

    // ponytail: placeholder until notifications exist.
    private var notificationsPlaceholder: some View {
        VStack(spacing: 0) {
            Masthead(title: "Notifications")
            Spacer()
            if eyebrowsRaised {
                Text("🤨").font(.system(size: 90))
            } else {
                VStack(spacing: Style.Space.lg) {
                    Image(systemName: "hammer")
                        .font(.system(size: 34))
                        .foregroundStyle(Style.meta)
                    Text("Under construction...")
                        .font(Style.body).foregroundStyle(Style.meta)
                    Text("Tap for gay porn")
                        .font(Style.eyebrow).foregroundStyle(Style.meta)
                        .onTapGesture { eyebrowsRaised = true }
                }
            }
            Spacer()
        }
        .background(Style.chrome)
    }

    // MARK: Nav bar

    private var navBar: some View {
        HStack {
            Button { tab = .feed } label: { navIcon("house.fill", active: tab == .feed) }
            Button { tab = .circles } label: { navIcon("circle.circle", active: tab == .circles) }
            Button { composing = true } label: { compose }
            Button { tab = .notifications } label: { navIcon("bell", active: tab == .notifications) }
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
