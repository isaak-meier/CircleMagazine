//
//  RootTabView.swift
//  CircleMagazine
//
//  The signed-in root: owns the nav bar and the selected tab (Circles home +
//  Account), swapping the screen above a persistent bar. Tapping a circle bubble
//  ripple-reveals that circle's magazine over the top. The magazine IS the
//  circle, so there's no global feed tab and compose lives inside a circle.
//

import SwiftUI

struct RootTabView: View {
    let factory: ViewModelFactory
    let account: AccountManager

    /// Built once from the signed-in user; @State keeps it (and its loaded
    /// circle list) alive across renders instead of refetching each time.
    @State private var circlesVM: CirclesViewModel

    init(factory: ViewModelFactory, account: AccountManager, me: User) {
        self.factory = factory
        self.account = account
        _circlesVM = State(initialValue: factory.makeCirclesVM(me: me))
    }

    @State private var tab: Tab = .circles

    /// Presentation data for the circle currently opened into its magazine —
    /// the bubble tone (roster header) and tap origin (ripple). The circle's VM
    /// is owned separately in `circleVM` so its state survives re-renders.
    struct EnteredCircle {
        let tone: CircleBubbleLayout.BubbleTone
        let origin: CGPoint
    }
    @State private var entered: EnteredCircle?
    @State private var circleVM: CircleViewModel?
    @State private var chatRevealed = false
    /// Invite code from a circlemagazine://join?code=… deep link, handed to the
    /// Circles tab which opens its join sheet prefilled.
    @State private var pendingJoinCode: String?

    enum Tab { case circles, account }

    var body: some View {
        // The nav bar sits outside the ripple, so entering a circle swaps only
        // the screen above it — you never lose your way back to Account.
        VStack(spacing: 0) {
            ZStack {
                if let entered, let circleVM {
                    CircleMagazineView(vm: circleVM, tone: entered.tone, onBack: exitCircle)
                }
                // Kept in the hierarchy (hidden, not removed) so tab state like
                // the Circles bubble physics survives a trip into a magazine.
                tabs
                    .opacity(chatRevealed ? 0 : 1)
                    .allowsHitTesting(!chatRevealed)
                    // wave: false — the magazine's webviews beneath can't take
                    // the Metal shader (they'd render as red boxes); hole-mask only.
                    .rippleReveal(origin: entered?.origin, wave: false) { chatRevealed = true }
            }
            navBar
        }
        .background(Style.chrome)
        .coordinateSpace(name: "root")
        // ponytail: URLs are dropped if this view isn't up yet (app cold-starts
        // signed out) — stash the code at App level if that ever matters.
        .onOpenURL { url in
            guard url.scheme == "circlemagazine", url.host() == "join",
                  let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "code" })?.value
            else { return }
            exitCircle()
            tab = .circles
            pendingJoinCode = code
        }
    }

    /// A tab tap from inside a circle backs out of it first — the bar is now
    /// always reachable, so it has to mean "leave here and go there".
    private func select(_ destination: Tab) {
        exitCircle()
        tab = destination
    }

    private func exitCircle() {
        entered = nil
        circleVM = nil
        chatRevealed = false
    }

    private var tabs: some View {
        ZStack {
            CirclesView(vm: circlesVM,
                        active: tab == .circles && entered == nil,
                        joinCode: $pendingJoinCode) { summary, tone, origin in
                guard case .signedIn(let user) = account.authState else { return }
                entered = EnteredCircle(tone: tone, origin: origin)
                circleVM = factory.makeCircleVM(summary, me: user)
            }
                .opacity(tab == .circles ? 1 : 0).allowsHitTesting(tab == .circles)
            AccountView(account: account, onEditionSourceChanged: factory.reset)
                .opacity(tab == .account ? 1 : 0).allowsHitTesting(tab == .account)
        }
    }

    // MARK: Nav bar

    private var navBar: some View {
        HStack {
            Button { select(.circles) } label: { navIcon("circle.circle", active: tab == .circles) }
            Button { select(.account) } label: { navIcon("person", active: tab == .account) }
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
}

#Preview {
    let db = DatabaseService()
    return RootTabView(
        factory: ViewModelFactory(db: db),
        account: AccountManager(db: db),
        me: User(id: UUID(), username: "You", bio: nil, avatarUrl: nil, role: nil,
                 followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil))
}
