//
//  CircleMagazineView.swift
//  CircleMagazine
//
//  A circle's edition, opened by tapping its bubble. The magazine IS the circle:
//  the feed body scoped to this circle, with a masthead that carries a back
//  chevron, a members button (roster sheet), and a compose button (posts into
//  this circle's edition). Binds to CircleViewModel — no service in sight.
//

import SwiftUI

struct CircleMagazineView: View {
    let vm: CircleViewModel
    /// Bubble tone, for the members sheet header. Presentation/navigation data
    /// from the tap, not a domain concern — so it rides alongside the VM.
    let tone: CircleBubbleLayout.BubbleTone
    let onBack: () -> Void

    @State private var showMembers = false
    @State private var composing = false

    var body: some View {
        phase
            .task { await vm.issue.appear() }
            .sheet(isPresented: $showMembers) {
                CircleMembersView(vm: vm, tone: tone) { showMembers = false }
            }
            // Refresh on dismiss, not inside the sheet's own callback: swiping
            // the sheet away is as much a way out as the confirmation's button,
            // and a post that only shows up when you leave the "right" way
            // looks like it didn't save.
            //
            // Both reloads, because a submission lands in the draft while the
            // screen may be showing either phase: the chat gains an event row,
            // and the edition reloads in case this post is what opened it.
            .sheet(isPresented: $composing) {
                Task { await vm.chat.appear(); await vm.issue.refresh() }
            } content: {
                ComposeView(model: vm.issue.composeVM()) { composing = false }
            }
    }

    /// Entering a circle renders its CURRENT PHASE, not an empty state: a live
    /// edition is the magazine, otherwise the week is still being assembled and
    /// the circle is its chat.
    /// ponytail: chat IS the compose screen for now — no submission staging,
    /// no "who's contributed" roster in the thread. Build those when the
    /// compose phase needs to do more than talk.
    @ViewBuilder private var phase: some View {
        if case .composing = vm.issue.state {
            CircleChatView(vm: vm.chat, tone: tone, onBack: onBack,
                           onMembers: { showMembers = true },
                           onCompose: { composing = true })
        } else {
            CardFeedView(vm: vm.issue, me: vm.me, title: vm.name,
                         mastheadLeading: AnyView(backButton),
                         mastheadTrailing: AnyView(controls))
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Style.ink)
        }
    }

    private var controls: some View {
        HStack(spacing: Style.Space.lg) {
            Button { showMembers = true } label: {
                Image(systemName: "person.2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Style.ink)
            }
            Button { composing = true } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Style.ink)
            }
        }
    }
}

#Preview {
    let me = User(id: UUID(), username: "You", bio: nil, avatarUrl: nil, role: nil,
                  followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    let summary = CircleSummary(
        circle: Circle(id: UUID(), name: "Dean St.", createdBy: me.id, createdAt: nil,
                       inviteCode: "ABC123"),
        members: [me])
    let db = DatabaseService()
    let vm = CircleViewModel(summary: summary, db: db, me: me,
                             issue: .preview(.loaded(Magazine.sample)),
                             chat: ChatViewModel(db: db, summary: summary, me: me))
    return CircleMagazineView(vm: vm, tone: CircleBubbleLayout.slots[0].tone, onBack: {})
}
