//
//  CircleChatView.swift
//  CircleMagazine
//
//  The circle chat page (from the Circle Chat.dc.html mockup): header with the
//  circle's tone badge and member line, an edition-status strip with a live
//  "closes in" countdown, a grouped message thread, and the input bar.
//
//  ponytail: messages are in-memory only — there's no messages table in the
//  schema yet; add one + Supabase Realtime when chat needs to persist.
//

import SwiftUI

// MARK: - Messages

struct ChatMessage: Identifiable {
    enum Kind {
        case text(String)
        case submission  // "X submitted a piece to this week's edition"
    }

    let id = UUID()
    let author: User
    let kind: Kind
    let sentAt: Date

    var isEvent: Bool {
        if case .submission = kind { return true }
        return false
    }
}

enum ChatRun {
    /// First/last-in-run flags for the message at `i` — they drive avatar,
    /// name label, timestamp, and corner radii. Like the mockup, event rows
    /// don't break a run of messages from the same author.
    static func flags(at i: Int, in messages: [ChatMessage]) -> (first: Bool, last: Bool) {
        let m = messages[i]
        let prev = messages[..<i].last { !$0.isEvent }
        let next = messages[(i + 1)...].first { !$0.isEvent }
        return (prev?.author.id != m.author.id, next?.author.id != m.author.id)
    }
}

// MARK: - Edition countdown

/// The "closes in" clock — counts to the end of Saturday, rolling to next week
/// once passed. Port of the mockup's getCountdown().
enum EditionCountdown {
    static func deadline(after now: Date, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: now)  // 1 = Sunday … 7 = Saturday
        let toSaturday = (7 - weekday + 7) % 7
        let saturday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: toSaturday, to: now)!)
        let deadline = calendar.date(byAdding: .day, value: 1, to: saturday)!
        return deadline > now ? deadline : calendar.date(byAdding: .day, value: 7, to: deadline)!
    }

    /// "2d 05h 41m", or "05h 41m 12s" inside the final day.
    static func string(from now: Date, calendar: Calendar = .current) -> String {
        var s = Int(deadline(after: now, calendar: calendar).timeIntervalSince(now).rounded())
        let d = s / 86_400; s %= 86_400
        let h = s / 3_600; s %= 3_600
        let m = s / 60; s %= 60
        func pad(_ n: Int) -> String { String(format: "%02d", n) }
        return d > 0 ? "\(d)d \(pad(h))h \(pad(m))m" : "\(pad(h))h \(pad(m))m \(pad(s))s"
    }
}

// MARK: - Screen

struct CircleChatView: View {
    let summary: CircleSummary
    let tone: CircleBubbleLayout.BubbleTone
    let me: User
    let onBack: () -> Void

    @State private var messages: [ChatMessage]
    @State private var draft = ""
    @State private var showInvite = false

    init(summary: CircleSummary, tone: CircleBubbleLayout.BubbleTone, me: User,
         seed: [ChatMessage] = [], onBack: @escaping () -> Void) {
        self.summary = summary
        self.tone = tone
        self.me = me
        self.onBack = onBack
        _messages = State(initialValue: seed)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            editionStrip
            thread
            inputBar
        }
        .background(Style.chrome)
        .sheet(isPresented: $showInvite) { InviteSheet(summary: summary) }
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
                Text(summary.name)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Style.ink)
                Text(memberLine)
                    .font(.system(size: 11)).foregroundStyle(Style.meta)
                    .lineLimit(1)
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

    // The circle's tone badge with the first other member's avatar tucked
    // behind it, like the mockup's cluster.
    private var avatarCluster: some View {
        ZStack(alignment: .topLeading) {
            Text(String(summary.name.prefix(1)))
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundStyle(tone.fg)
                .frame(width: 34, height: 34)
                .background(SwiftUI.Circle()
                    .fill(RadialGradient(colors: [tone.hi, tone.lo],
                                         center: UnitPoint(x: 0.34, y: 0.28),
                                         startRadius: 0, endRadius: 26)))
            if let other = summary.members.first(where: { $0.id != me.id }) {
                memberAvatar(other, diameter: 22, fontSize: 8.5)
                    .overlay(SwiftUI.Circle().stroke(Style.chrome, lineWidth: 2))
                    .offset(x: 16, y: 8)
            }
        }
        .frame(width: 38, height: 34, alignment: .topLeading)
    }

    private var memberLine: String {
        let names = summary.members.prefix(3).map { firstName($0.username) }
        let rest = summary.members.count - names.count
        return names.joined(separator: ", ") + (rest > 0 ? " +\(rest) more" : "")
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
                if let editor {
                    HStack(spacing: 6) {
                        Text(firstName(editor.username))
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
                    Text(EditionCountdown.string(from: context.date))
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

    // The circle's creator wears the editor hat; falls back to the first member.
    private var editor: User? {
        summary.members.first { $0.id == summary.circle.createdBy } ?? summary.members.first
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
                ForEach(Array(messages.enumerated()), id: \.element.id) { i, message in
                    if message.isEvent {
                        eventRow(message)
                    } else {
                        let run = ChatRun.flags(at: i, in: messages)
                        messageRow(message, first: run.first, last: run.last)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
    }

    private func eventRow(_ message: ChatMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "book")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Style.paper)
                .frame(width: 20, height: 20)
                .background(SwiftUI.Circle().fill(Style.ink))
            (Text(firstName(message.author.username)).fontWeight(.semibold).foregroundStyle(Style.ink)
             + Text(" submitted a piece to this week's edition"))
                .font(.system(size: 11.5))
                .foregroundStyle(Color(hex: 0x4A4742))
        }
        .padding(.vertical, 7).padding(.leading, 10).padding(.trailing, 13)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xF1EFEA)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Style.rule, lineWidth: 1))
        .padding(.vertical, 12)
    }

    private func messageRow(_ message: ChatMessage, first: Bool, last: Bool) -> some View {
        let isMe = message.author.id == me.id
        guard case .text(let text) = message.kind else { return AnyView(EmptyView()) }
        return AnyView(HStack(alignment: .bottom, spacing: 8) {
            if !isMe {
                if first {
                    memberAvatar(message.author, diameter: 22, fontSize: 8.5)
                } else {
                    Color.clear.frame(width: 22, height: 1)
                }
            }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {
                if !isMe && first {
                    Text(firstName(message.author.username))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Style.meta)
                        .padding(.leading, 3)
                }
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(isMe ? Color(hex: 0xF4F2EE) : Color(hex: 0x2A2826))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(UnevenRoundedRectangle(cornerRadii: bubbleRadii(isMe: isMe, first: first, last: last),
                                                       style: .continuous)
                        .fill(isMe ? Style.edition : Color(hex: 0xF1EFEA)))
                if last {
                    Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color(hex: 0xB4AFA8))
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: 280, alignment: isMe ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
        .padding(.top, first ? 12 : 2))
    }

    /// The mockup's grouped-bubble corners: square-ish toward the run's
    /// middle, a small tail at the run's end on the author's side.
    private func bubbleRadii(isMe: Bool, first: Bool, last: Bool) -> RectangleCornerRadii {
        if isMe {
            return RectangleCornerRadii(topLeading: 18, bottomLeading: 18,
                                        bottomTrailing: last ? 4 : 6, topTrailing: first ? 18 : 6)
        }
        return RectangleCornerRadii(topLeading: first ? 18 : 6, bottomLeading: last ? 4 : 6,
                                    bottomTrailing: 18, topTrailing: 18)
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: Style.Space.sm) {
            TextField("Message \(summary.name)", text: $draft)
                .font(.system(size: 13.5))
                .padding(.horizontal, Style.Space.lg).padding(.vertical, 10)
                .background(Capsule().fill(Style.paper))
                .overlay(Capsule().stroke(Style.rule, lineWidth: 1))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Style.paper)
                    .frame(width: 32, height: 32)
                    .background(SwiftUI.Circle().fill(Style.ink))
            }
            .disabled(trimmedDraft.isEmpty)
            .opacity(trimmedDraft.isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, Style.Space.md)
        .padding(.top, 9)
        .background(Style.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Style.rule).frame(height: 1) }
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(author: me, kind: .text(text), sentAt: .now))
        draft = ""
    }

    // MARK: Small helpers

    private func memberAvatar(_ user: User, diameter: CGFloat, fontSize: CGFloat) -> some View {
        let index = summary.members.firstIndex { $0.id == user.id } ?? 0
        return Text(initials(user.username))
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(SwiftUI.Circle().fill(Self.avatarColors[index % Self.avatarColors.count]))
    }

    private static let avatarColors: [Color] = [
        Color(hex: 0x3E6E8E), Color(hex: 0x8E5A3E), Color(hex: 0x4A7A52), Color(hex: 0x6A5A8E),
    ]

    private func firstName(_ username: String) -> String {
        String(username.split(separator: " ").first ?? Substring(username))
    }

    private func initials(_ username: String) -> String {
        let words = username.split(separator: " ")
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String(username.prefix(2)).uppercased()
    }
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
    return CircleChatView(
        summary: summary, tone: CircleBubbleLayout.slots[0].tone, me: me,
        seed: [
            msg(dave, "ok who's in for the roof thing saturday"),
            msg(dave, "bringing the good speaker this time"),
            msg(arnell, "depends what time, I've got the market till 2"),
            msg(me, "I'm in either way, just tell me when to show up"),
            msg(sawyer, "same, flexible"),
            msg(dave, "phil it was one (1) incident and dean's fine"),
            msg(me, "he's still fine? dean???"),
            ChatMessage(author: sawyer, kind: .submission, sentAt: .now),
        ],
        onBack: {})
}
