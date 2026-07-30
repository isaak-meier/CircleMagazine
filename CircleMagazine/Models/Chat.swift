//
//  Chat.swift
//  CircleMagazine
//
//  The circle chat's domain: a message and the rule for grouping consecutive
//  messages from one author into a run. No presentation here — ChatViewModel
//  turns these into rows the view renders.
//

import Foundation

/// Someone putting a piece into the edition being assembled: who and when, and
/// deliberately nothing else. The content stays sealed until the issue
/// publishes — that's the compose phase's whole shape.
struct Submission {
    let authorId: UUID
    let at: Date
}

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

    var text: String {
        if case .text(let t) = kind { return t }
        return ""
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
