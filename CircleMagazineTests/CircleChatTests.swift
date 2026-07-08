//
//  CircleChatTests.swift
//  CircleMagazineTests
//
//  The chat page's date math (edition countdown) and message-run grouping.
//

import Foundation
import Testing
@testable import CircleMagazine

struct CircleChatTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test func countdownMidweekShowsDays() {
        // Wed Jul 1 2026, noon → edition closes end of Sat Jul 4.
        #expect(EditionCountdown.string(from: date(2026, 7, 1, 12), calendar: cal) == "3d 12h 00m")
    }

    @Test func countdownFinalDayShowsSeconds() {
        // Saturday noon — inside the final day, still counting to tonight.
        #expect(EditionCountdown.string(from: date(2026, 7, 4, 12), calendar: cal) == "12h 00m 00s")
    }

    @Test func countdownRollsToNextWeekAfterClose() {
        // Sunday 00:00, just past the close → a full week out.
        #expect(EditionCountdown.string(from: date(2026, 7, 5), calendar: cal) == "7d 00h 00m")
    }

    @Test func runFlagsGroupByAuthorAcrossEvents() {
        func user() -> User {
            User(id: UUID(), username: "u", bio: nil, avatarUrl: nil, role: nil,
                 followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
        }
        let a = user(), b = user()
        let messages: [ChatMessage] = [
            ChatMessage(author: a, kind: .text("1"), sentAt: .now),
            ChatMessage(author: a, kind: .text("2"), sentAt: .now),
            ChatMessage(author: b, kind: .submission, sentAt: .now),  // shouldn't break a's run
            ChatMessage(author: a, kind: .text("3"), sentAt: .now),
            ChatMessage(author: b, kind: .text("4"), sentAt: .now),
        ]
        #expect(ChatRun.flags(at: 0, in: messages) == (true, false))
        #expect(ChatRun.flags(at: 1, in: messages) == (false, false))
        #expect(ChatRun.flags(at: 3, in: messages) == (false, true))
        #expect(ChatRun.flags(at: 4, in: messages) == (true, true))
    }
}
