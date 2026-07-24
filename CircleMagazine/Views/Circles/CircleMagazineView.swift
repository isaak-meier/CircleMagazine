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
        CardFeedView(vm: vm.issue, me: vm.me, title: vm.name,
                     mastheadLeading: AnyView(backButton),
                     mastheadTrailing: AnyView(controls))
            .sheet(isPresented: $showMembers) {
                CircleMembersView(vm: vm, tone: tone) { showMembers = false }
            }
            .sheet(isPresented: $composing) {
                ComposeView(model: vm.issue.composeVM()) {
                    composing = false
                    await vm.issue.refresh()   // show the new post
                }
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
    let vm = CircleViewModel(summary: summary, db: DatabaseService(), me: me,
                             issue: .preview(.loaded(Magazine.sample)))
    return CircleMagazineView(vm: vm, tone: CircleBubbleLayout.slots[0].tone, onBack: {})
}
