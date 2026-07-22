//
//  CircleMembersView.swift
//  CircleMagazine
//
//  The circle screen behind a bubble tap (standing in for chat, which is
//  parked for now): the member roster split into who has submitted to this
//  week's edition and who hasn't, plus the invite entry point.
//

import SwiftUI

struct CircleMembersView: View {
    let db: DatabaseService
    let summary: CircleSummary
    let tone: CircleBubbleLayout.BubbleTone
    let me: User
    let onBack: () -> Void

    /// nil while loading; ids of members with a page in the live issue after.
    @State private var submitters: Set<UUID>?
    @State private var loadError: String?
    @State private var showInvite = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Style.chrome)
        .sheet(isPresented: $showInvite) { InviteSheet(summary: summary) }
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Style.ink)
                    .frame(width: 30, alignment: .leading)
            }
            Text(String(summary.name.prefix(1)))
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundStyle(tone.fg)
                .frame(width: 34, height: 34)
                .background(SwiftUI.Circle()
                    .fill(RadialGradient(colors: [tone.hi, tone.lo],
                                         center: UnitPoint(x: 0.34, y: 0.28),
                                         startRadius: 0, endRadius: 26)))
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.name)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Style.ink)
                Text("\(summary.members.count) member\(summary.members.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(Style.meta)
            }
            Spacer()
            Button { showInvite = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Style.ink)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Style.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Style.rule).frame(height: 1) }
    }

    // MARK: Roster

    @ViewBuilder
    private var content: some View {
        if let submitters {
            let submitted = summary.members.filter { submitters.contains($0.id) }
            let pending = summary.members.filter { !submitters.contains($0.id) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let loadError {
                        ErrorBanner(message: loadError).padding(.top, Style.Space.md)
                    }
                    if !submitted.isEmpty {
                        sectionHeader("SUBMITTED THIS WEEK", count: submitted.count)
                        ForEach(submitted, id: \.id) { memberRow($0, submitted: true) }
                    }
                    if !pending.isEmpty {
                        sectionHeader("NOT YET", count: pending.count)
                        ForEach(pending, id: \.id) { memberRow($0, submitted: false) }
                    }
                }
                .padding(.horizontal, Style.Space.lg)
                .padding(.bottom, Style.Space.xl)
            }
            .scrollIndicators(.hidden)
        } else {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text("· \(count)").foregroundStyle(Style.meta.opacity(0.7))
        }
        .font(.system(size: 9.5, weight: .medium, design: .monospaced)).tracking(1)
        .foregroundStyle(Style.meta)
        .padding(.top, Style.Space.xl).padding(.bottom, Style.Space.sm)
    }

    private func memberRow(_ user: User, submitted: Bool) -> some View {
        HStack(spacing: Style.Space.md) {
            avatar(user)
            HStack(spacing: 6) {
                Text(user.username + (user.id == me.id ? " (you)" : ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Style.ink)
                if user.id == summary.circle.createdBy {
                    Text("EDITOR")
                        .font(.system(size: 8, weight: .semibold)).tracking(1)
                        .foregroundStyle(Style.edition)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .stroke(Style.rule, lineWidth: 1))
                }
            }
            Spacer()
            Image(systemName: submitted ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 16))
                .foregroundStyle(submitted ? Style.ink : Style.meta.opacity(0.6))
        }
        .padding(.vertical, Style.Space.sm + 2)
        .overlay(alignment: .bottom) { Rectangle().fill(Style.rule).frame(height: 0.5) }
    }

    private func avatar(_ user: User) -> some View {
        let index = summary.members.firstIndex { $0.id == user.id } ?? 0
        let colors: [Color] = [Color(hex: 0x3E6E8E), Color(hex: 0x8E5A3E),
                               Color(hex: 0x4A7A52), Color(hex: 0x6A5A8E)]
        let words = user.username.split(separator: " ")
        let initials = words.count >= 2
            ? String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
            : String(user.username.prefix(2)).uppercased()
        return Text(initials)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(SwiftUI.Circle().fill(colors[index % colors.count]))
    }

    private func load() async {
        do {
            submitters = try await db.submitterIds(among: summary.members.map(\.id))
        } catch {
            loadError = "Couldn't load submissions — \(error.localizedDescription)"
            submitters = []  // fall back to everyone in "not yet"
        }
    }
}

// MARK: - Preview

#Preview {
    let user = { (name: String) in
        User(id: UUID(), username: name, bio: nil, avatarUrl: nil, role: nil,
             followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    }
    let me = user("You Person")
    let dave = user("Dave Slater"), arnell = user("Arnell R"), sawyer = user("Sawyer W")
    let summary = CircleSummary(
        circle: Circle(id: UUID(), name: "Dean St.", createdBy: arnell.id, createdAt: nil,
                       inviteCode: "ABC123"),
        members: [dave, arnell, sawyer, me])
    return CircleMembersView(db: DatabaseService(), summary: summary,
                             tone: CircleBubbleLayout.slots[0].tone, me: me, onBack: {})
}
