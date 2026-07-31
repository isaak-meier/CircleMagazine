//
//  EditionNotifications.swift
//  CircleMagazine
//
//  "This week's edition is out" — the nudge that closes the weekly loop.
//
//  LOCAL notifications, not push, and that's not a shortcut: an edition going
//  live is a *date passing*, not an event anyone fires. `publish_date < today`
//  (see `Issue.liveCutoff`), cutoff Saturday midnight, so every publish moment
//  for the rest of the year is already knowable on the device. A server push
//  would need APNs keys, a device-token table, an edge function and pg_cron to
//  deliver the same notification at the same second — with a backend that can
//  fail, in exchange for nothing.
//
//  It's the same reason there's no publish job: liveness is derived.
//
//  What this CAN'T do, and what would need real push:
//  - anything reactive — "Dave reacted to your post", "3 new comments"
//  - post counts in the body: at schedule time the edition hasn't been written
//  - reaching someone who never opens the app again (nothing is scheduled for a
//    device that never launches), or a circle joined on another device until
//    this one next launches
//

import Foundation
import UserNotifications

/// Schedules each circle's publication days on this device.
///
/// A struct of statics rather than a service on the DI graph: it holds no state
/// (`UNUserNotificationCenter` is the store) and nothing about it is worth
/// injecting — the tests that matter are on the pure date/content helpers below.
enum EditionNotifications {
    /// How many upcoming Sundays to schedule per circle. iOS keeps only the
    /// nearest 64 pending local notifications per app, so this times your circle
    /// count has to stay under that; four weeks × eight circles is 32.
    /// Rescheduled on every launch anyway, so the horizon only has to outlast
    /// the gap between two launches.
    static let weeksAhead = 4

    private static var center: UNUserNotificationCenter { .current() }

    /// True inside a test run (the tests use the app as their host) and in an
    /// Xcode preview — neither should ever prompt for permission.
    private static var isTesting: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// Ask once, and only when there's something to be notified about — asking
    /// at launch, before the app has shown its value, is how you get denied
    /// forever. Returns whether we're allowed to post.
    @discardableResult
    static func requestPermission() async -> Bool {
        // The unit tests launch the app as their host, so without this the very
        // first `load()` puts a system permission alert on screen and `xcodebuild
        // test` sits there until it times out. Same reason `DatabaseService`
        // sniffs out Preview mode.
        guard !isTesting else { return false }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Replace this device's schedule with one notification per circle per
    /// upcoming publication day.
    ///
    /// Replace, not append: circles come and go, and identifiers are derived from
    /// circle + day, so re-running this is idempotent — no duplicate nudges for a
    /// circle you're still in, and nothing left behind for one you left.
    static func reschedule(for circles: [(id: UUID, name: String)],
                           now: Date = .now, calendar: Calendar = .current) async {
        center.removeAllPendingNotificationRequests()
        guard !circles.isEmpty, await requestPermission() else { return }

        for circle in circles {
            for day in publicationDays(from: now, calendar: calendar) {
                let content = UNMutableNotificationContent()
                content.title = circle.name
                content.body = body(forEditionPublishing: day, calendar: calendar)
                content.sound = .default
                // Groups a circle's nudges together in Notification Centre, and
                // lets the tap open the right circle later.
                content.threadIdentifier = circle.id.uuidString
                content.userInfo = ["circleId": circle.id.uuidString]

                var when = calendar.dateComponents([.year, .month, .day], from: day)
                when.hour = 9   // ponytail: 9am local. Per-member quiet hours if anyone asks.
                let request = UNNotificationRequest(
                    identifier: identifier(circleId: circle.id, day: day, calendar: calendar),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
                try? await center.add(request)
            }
        }
    }

    /// The next `weeksAhead` days an edition becomes readable: the Sundays after
    /// each Saturday deadline. Uses `EditionCountdown` so the notification can't
    /// name a different day than the masthead and the countdown do.
    static func publicationDays(from now: Date, calendar: Calendar = .current) -> [Date] {
        let candidates: [Date] = (0..<weeksAhead).compactMap { week in
            guard let weekFromNow = calendar.date(byAdding: .day, value: week * 7, to: now)
            else { return nil }
            // `deadline` IS the midnight the edition opens at — that's the day
            // it's readable, and it's already strictly in the future.
            return EditionCountdown.deadline(after: weekFromNow, calendar: calendar)
        }
        // Two adjacent weeks can land on the same deadline when `now` is close to
        // it, so de-dupe by day rather than trusting the stride.
        return candidates.reduce(into: [Date]()) { days, day in
            if !days.contains(where: { calendar.isDate($0, inSameDayAs: day) }) { days.append(day) }
        }
    }

    /// "The July 26 edition is out. \(n) posts inside" is what push would buy;
    /// what a date alone can say is the publication itself, which is the thing a
    /// magazine announces anyway.
    static func body(forEditionPublishing day: Date, calendar: Calendar = .current) -> String {
        // The edition is named for the Saturday it closed on — the day BEFORE it
        // opens — same as the masthead. Naming it for today would call it by a
        // date the issue itself doesn't carry.
        let closed = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        return "The \(monthDay.string(from: closed)) edition is out."
    }

    /// Stable per circle per day, so rescheduling overwrites rather than stacks.
    static func identifier(circleId: UUID, day: Date, calendar: Calendar = .current) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: day)
        return "edition-\(circleId.uuidString)-\(d.year ?? 0)-\(d.month ?? 0)-\(d.day ?? 0)"
    }

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM d"
        return f
    }()

    #if DEBUG
    /// Fires the real thing in a few seconds, so the copy and the grouping can be
    /// seen without waiting for Sunday. Background the app to see the banner.
    static func fireTestNotification(circleName: String = "Bean") async {
        guard await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = circleName
        content.body = body(forEditionPublishing: EditionCountdown.deadline(after: .now))
        content.sound = .default
        try? await center.add(UNNotificationRequest(
            identifier: "edition-test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }
    #endif
}
