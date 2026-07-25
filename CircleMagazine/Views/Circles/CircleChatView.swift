//
//  CircleChatView.swift
//  CircleMagazine
//
//  The circle chat page (from the Circle Chat.dc.html mockup): header with the
//  circle's tone badge and member line, an edition-status strip with a live
//  "closes in" countdown, a grouped message thread, and the input bar.
//
//  Presentation only — every string, grouping flag, and command comes from
//  ChatViewModel. Layout, colour, and corner radii are this file's business.
//

import SwiftUI

// MARK: - Screen

struct CircleChatView: View {
    @Bindable var vm: ChatViewModel
    /// Bubble tone from the tapped bubble — navigation/presentation data, not a
    /// domain concern, so it rides alongside the VM.
    let tone: CircleBubbleLayout.BubbleTone
    let onBack: () -> Void
    /// Roster and compose are the same actions the edition phase offers, so the
    /// owning screen keeps the sheets and hands us the triggers.
    let onMembers: () -> Void
    let onCompose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            editionStrip
            thread
            inputBar
        }
        .background(Style.chrome)
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
            avatarCluster
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.circleName)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Style.ink)
                Text(vm.memberLine)
                    .font(.system(size: 11)).foregroundStyle(Style.meta)
                    .lineLimit(1)
            }
            Spacer()
            // Plus, not square.and.pencil: in a chat header a plus reads as
            // "add something to this week's edition". Invite moved inside the
            // roster sheet, which is where you go looking for people anyway.
            HStack(spacing: Style.Space.lg) {
                Button(action: onMembers) {
                    Image(systemName: "person.2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Style.ink)
                }
                Button(action: onCompose) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Style.ink)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Style.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Style.rule).frame(height: 1) }
    }

    // The circle's tone badge with another member's avatar tucked behind it,
    // like the mockup's cluster.
    private var avatarCluster: some View {
        ZStack(alignment: .topLeading) {
            Text(vm.monogram)
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundStyle(tone.fg)
                .frame(width: 34, height: 34)
                .background(SwiftUI.Circle()
                    .fill(RadialGradient(colors: [tone.hi, tone.lo],
                                         center: UnitPoint(x: 0.34, y: 0.28),
                                         startRadius: 0, endRadius: 26)))
            if let other = vm.clusterAvatar {
                avatar(initials: other.initials, index: other.avatarIndex,
                       diameter: 22, fontSize: 8.5)
                    .overlay(SwiftUI.Circle().stroke(Style.chrome, lineWidth: 2))
                    .offset(x: 16, y: 8)
            }
        }
        .frame(width: 38, height: 34, alignment: .topLeading)
    }

    // MARK: Edition strip

    private var editionStrip: some View {
        HStack(spacing: 11) {
            Image(systemName: "book")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Style.paper)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Style.ink))
            VStack(alignment: .leading, spacing: 2) {
                Text("THIS WEEK'S EDITION")
                    .font(.system(size: 8, weight: .semibold)).tracking(1.3)
                    .foregroundStyle(Color(hex: 0x9A958E))
                if let editorName = vm.editorName {
                    HStack(spacing: 6) {
                        Text(editorName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x2A2826))
                        Text("EDITOR")
                            .font(.system(size: 8, weight: .semibold)).tracking(1)
                            .foregroundStyle(Style.edition)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .stroke(Color(hex: 0xC9C5BD), lineWidth: 1))
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("CLOSES IN")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(0.8)
                    .foregroundStyle(Color(hex: 0x9A958E))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(vm.countdown(at: context.date))
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xB84C4C))
                }
            }
        }
        .padding(.horizontal, Style.Space.lg)
        .padding(.vertical, Style.Space.md)
        .background(Color(hex: 0xF1EFEA))
        .overlay(alignment: .bottom) { Rectangle().fill(Style.rule).frame(height: 1) }
    }

    // MARK: Thread

    private var thread: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text("TODAY")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced)).tracking(1)
                    .foregroundStyle(Color(hex: 0x9A958E))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Style.rule))
                    .padding(.top, 6).padding(.bottom, 6)
                ForEach(vm.rows) { row in
                    if row.isEvent {
                        eventRow(row)
                    } else {
                        messageRow(row)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
    }

    private func eventRow(_ row: ChatViewModel.Row) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "book")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Style.paper)
                .frame(width: 20, height: 20)
                .background(SwiftUI.Circle().fill(Style.ink))
            (Text(row.authorName).fontWeight(.semibold).foregroundStyle(Style.ink)
             + Text(" submitted a piece to this week's edition"))
                .font(.system(size: 11.5))
                .foregroundStyle(Color(hex: 0x4A4742))
        }
        .padding(.vertical, 7).padding(.leading, 10).padding(.trailing, 13)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xF1EFEA)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Style.rule, lineWidth: 1))
        .padding(.vertical, 12)
    }

    private func messageRow(_ row: ChatViewModel.Row) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !row.isMine {
                if row.isRunStart {
                    avatar(initials: row.initials, index: row.avatarIndex,
                           diameter: 22, fontSize: 8.5)
                } else {
                    Color.clear.frame(width: 22, height: 1)
                }
            }
            VStack(alignment: row.isMine ? .trailing : .leading, spacing: 3) {
                if !row.isMine && row.isRunStart {
                    Text(row.authorName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Style.meta)
                        .padding(.leading, 3)
                }
                Text(row.text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(row.isMine ? Color(hex: 0xF4F2EE) : Color(hex: 0x2A2826))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(UnevenRoundedRectangle(cornerRadii: bubbleRadii(row),
                                                       style: .continuous)
                        .fill(row.isMine ? Style.edition : Color(hex: 0xF1EFEA)))
                if row.isRunEnd {
                    Text(row.time)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color(hex: 0xB4AFA8))
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: 280, alignment: row.isMine ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: row.isMine ? .trailing : .leading)
        .padding(.top, row.isRunStart ? 12 : 2)
    }

    /// The mockup's grouped-bubble corners: square-ish toward the run's
    /// middle, a small tail at the run's end on the author's side.
    private func bubbleRadii(_ row: ChatViewModel.Row) -> RectangleCornerRadii {
        if row.isMine {
            return RectangleCornerRadii(topLeading: 18, bottomLeading: 18,
                                        bottomTrailing: row.isRunEnd ? 4 : 6,
                                        topTrailing: row.isRunStart ? 18 : 6)
        }
        return RectangleCornerRadii(topLeading: row.isRunStart ? 18 : 6,
                                    bottomLeading: row.isRunEnd ? 4 : 6,
                                    bottomTrailing: 18, topTrailing: 18)
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: Style.Space.sm) {
            TextField("Message \(vm.circleName)", text: $vm.draft)
                .font(.system(size: 13.5))
                .padding(.horizontal, Style.Space.lg).padding(.vertical, 10)
                .background(Capsule().fill(Style.paper))
                .overlay(Capsule().stroke(Style.rule, lineWidth: 1))
                .onSubmit(vm.send)
            Button(action: vm.send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Style.paper)
                    .frame(width: 32, height: 32)
                    .background(SwiftUI.Circle().fill(Style.ink))
            }
            .disabled(!vm.canSend)
            .opacity(vm.canSend ? 1 : 0.35)
        }
        .padding(.horizontal, Style.Space.md)
        .padding(.top, 9)
        .background(Style.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Style.rule).frame(height: 1) }
    }

    // MARK: Small helpers

    private func avatar(initials: String, index: Int,
                        diameter: CGFloat, fontSize: CGFloat) -> some View {
        Text(initials)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(SwiftUI.Circle().fill(Self.avatarColors[index % Self.avatarColors.count]))
    }

    private static let avatarColors: [Color] = [
        Color(hex: 0x3E6E8E), Color(hex: 0x8E5A3E), Color(hex: 0x4A7A52), Color(hex: 0x6A5A8E),
    ]
}

// MARK: - Invite sheet

/// The circle's invite code, big and selectable, with a shortcut into Messages.
/// Lives here with the chat but is also the members screen's invite sheet.
struct InviteSheet: View {
    let summary: CircleSummary
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Style.Space.xl) {
            Text("Invite to \(summary.name)")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(Style.ink)
            Text("Share this code — friends enter it under Join a Circle.")
                .font(.system(size: 12)).foregroundStyle(Style.meta)
                .multilineTextAlignment(.center)
            Text(summary.circle.inviteCode)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .tracking(6)
                .foregroundStyle(Style.ink)
                .textSelection(.enabled)
                .padding(.horizontal, Style.Space.xl).padding(.vertical, Style.Space.md)
                .background(RoundedRectangle(cornerRadius: 12).fill(Style.paper))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Style.rule, lineWidth: 1))
            CirclePillButton(title: "Invite via Text", filled: true, height: 50) {
                let code = summary.circle.inviteCode
                let text = "Join my circle “\(summary.name)” on Circle Magazine — invite code \(code). Tap to join: circlemagazine://join?code=\(code)"
                let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "sms:?&body=\(encoded)") { openURL(url) }
            }
        }
        .padding(Style.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Style.chrome)
        .presentationDetents([.medium])
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
    let msg = { (author: User, text: String) in
        ChatMessage(author: author, kind: .text(text), sentAt: .now)
    }
    let vm = ChatViewModel(
        db: DatabaseService(), summary: summary, me: me,
        seed: [
            msg(dave, "ok who's in for the roof thing saturday"),
            msg(dave, "bringing the good speaker this time"),
            msg(arnell, "depends what time, I've got the market till 2"),
            msg(me, "I'm in either way, just tell me when to show up"),
            msg(sawyer, "same, flexible"),
            msg(dave, "phil it was one (1) incident and dean's fine"),
            msg(me, "he's still fine? dean???"),
            ChatMessage(author: sawyer, kind: .submission, sentAt: .now),
        ])
    return CircleChatView(vm: vm, tone: CircleBubbleLayout.slots[0].tone,
                          onBack: {}, onMembers: {}, onCompose: {})
}
