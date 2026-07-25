//
//  ChatViewModel.swift
//  CircleMagazine
//
//  The circle chat screen's ViewModel — the compose phase's screen. Owns the
//  thread and the draft, formats every string the header/strip/thread show, and
//  holds the services privately so CircleChatView never sees a Model.
//

import Foundation

@Observable @MainActor
final class ChatViewModel {
    /// One thread row, ready to render: the view does layout and colour, this
    /// decides text, grouping, and whose side it sits on.
    struct Row: Identifiable {
        let id: UUID
        let isEvent: Bool
        let isMine: Bool
        let text: String
        let authorName: String
        let initials: String
        /// Index into the view's avatar palette — stable per member.
        let avatarIndex: Int
        let isRunStart: Bool
        let isRunEnd: Bool
        let time: String
    }

    private let db: DatabaseService
    private let summary: CircleSummary
    private let me: User

    /// ponytail: in-memory only — there's no messages table in the schema yet;
    /// add one + Supabase Realtime when chat needs to persist.
    private var messages: [ChatMessage]

    var draft = ""

    init(db: DatabaseService, summary: CircleSummary, me: User, seed: [ChatMessage] = []) {
        self.db = db
        self.summary = summary
        self.me = me
        self.messages = seed
    }

    // MARK: Header

    var circleName: String { summary.name }

    /// The tone badge's letter.
    var monogram: String { String(summary.name.prefix(1)) }

    /// "Dave, Arnell, Sawyer +2 more"
    var memberLine: String {
        let names = summary.members.prefix(3).map { Self.firstName($0.username) }
        let rest = summary.members.count - names.count
        return names.joined(separator: ", ") + (rest > 0 ? " +\(rest) more" : "")
    }

    /// The member tucked behind the tone badge in the header cluster — the first
    /// one who isn't me. Nil in a circle of one.
    var clusterAvatar: (initials: String, avatarIndex: Int)? {
        guard let other = summary.members.first(where: { $0.id != me.id }) else { return nil }
        return (Self.initials(other.username), avatarIndex(of: other))
    }

    // MARK: Edition strip

    /// The circle's creator wears the editor hat; falls back to the first member.
    var editorName: String? {
        let editor = summary.members.first { $0.id == summary.circle.createdBy }
            ?? summary.members.first
        return editor.map { Self.firstName($0.username) }
    }

    /// "2d 05h 41m" — the view's TimelineView ticks and asks for each tick.
    func countdown(at now: Date) -> String { EditionCountdown.string(from: now) }

    // MARK: Thread

    var rows: [Row] {
        messages.indices.map { i in
            let m = messages[i]
            let run = ChatRun.flags(at: i, in: messages)
            return Row(
                id: m.id, isEvent: m.isEvent, isMine: m.author.id == me.id,
                text: m.text, authorName: Self.firstName(m.author.username),
                initials: Self.initials(m.author.username),
                avatarIndex: avatarIndex(of: m.author),
                isRunStart: run.first, isRunEnd: run.last,
                time: m.sentAt.formatted(date: .omitted, time: .shortened))
        }
    }

    // MARK: Commands

    var canSend: Bool { !trimmedDraft.isEmpty }

    func send() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(author: me, kind: .text(text), sentAt: .now))
        draft = ""
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Formatting

    private func avatarIndex(of user: User) -> Int {
        summary.members.firstIndex { $0.id == user.id } ?? 0
    }

    private static func firstName(_ username: String) -> String {
        String(username.split(separator: " ").first ?? Substring(username))
    }

    private static func initials(_ username: String) -> String {
        let words = username.split(separator: " ")
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String(username.prefix(2)).uppercased()
    }
}
