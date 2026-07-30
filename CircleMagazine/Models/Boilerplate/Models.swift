import Foundation

struct CircleMember: Codable {
    let circleId: UUID
    let userId: UUID
    let joinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case circleId = "circle_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

struct Circle: Codable {
    let id: UUID
    let name: String?
    let createdBy: UUID?
    let createdAt: Date?
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdBy = "created_by"
        case createdAt = "created_at"
        case inviteCode = "invite_code"
    }
}

struct Comment: Codable, Identifiable {
    let id: UUID
    let pageId: UUID
    let userId: UUID
    let body: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case userId = "user_id"
        case body
        case createdAt = "created_at"
    }
}

/// A comment paired with its author for display (author nil if the user row
/// couldn't be fetched).
struct CommentWithAuthor: Identifiable {
    let comment: Comment
    let author: User?
    var id: UUID { comment.id }
}

/// A photo someone took in response to a page. One per person per page — the DB
/// enforces it with UNIQUE(page_id, user_id), so reacting again replaces rather
/// than accumulates. `mediaPath` is a path in the private bucket, never a URL:
/// the feed signs it at render time, same as every other stored image.
nonisolated struct Reaction: Codable, Identifiable {
    let id: UUID
    let pageId: UUID
    let userId: UUID
    let mediaPath: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case userId = "user_id"
        case mediaPath = "media_path"
        case createdAt = "created_at"
    }
}

/// A reaction paired with its author, so a card can show whose face it is.
/// Author nil when that user row didn't come back — someone who left the circle.
struct ReactionWithAuthor: Identifiable {
    let reaction: Reaction
    let author: User?
    var id: UUID { reaction.id }
}

struct Engagement: Codable {
    let id: UUID
    let userId: UUID?
    let cardId: UUID?
    let watchPercent: Int?
    let scrollDepth: Int?
    let completed: Bool?
    let engagedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case cardId = "card_id"
        case watchPercent = "watch_percent"
        case scrollDepth = "scroll_depth"
        case completed
        case engagedAt = "engaged_at"
    }
}

struct Follow: Codable {
    let id: UUID
    let followerId: UUID?
    let followeeId: UUID?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case followerId = "follower_id"
        case followeeId = "followee_id"
        case createdAt = "created_at"
    }
}

struct Issue: Codable {
    let id: UUID
    let circleId: UUID
    let publishDate: String
    /// Vestigial — liveness is derived from `publishDate` (see `liveCutoff`).
    /// Nothing reads this; the column is left in place so old rows still decode.
    let isLive: Bool?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case publishDate = "publish_date"
        case isLive = "is_live"
        case createdAt = "created_at"
    }
}

extension Issue {
    /// `publish_date` ("2026-06-17") rendered for the masthead, e.g. "JUNE 17, 2026".
    /// Falls back to the raw string if it isn't a parseable date.
    var editionDate: String {
        guard let date = Self.dateParser.date(from: publishDate) else { return publishDate }
        return Self.editionFormatter.string(from: date).uppercased()
    }

    /// A day in `publish_date`'s wire format ("2026-06-17"). Same formatter as
    /// the parser, so writing and reading can't drift apart.
    static func publishDate(for date: Date) -> String { dateParser.string(from: date) }

    /// Liveness is **derived, not stored**: an edition is live once the Saturday
    /// it closes on is strictly in the past — i.e. from Sunday onward. An edition
    /// stamped with today is still being assembled, which is why the live filter
    /// is `<` and the draft filter is `>=`.
    ///
    /// Nothing writes `is_live`; there is no publish job to run late or not at
    /// all, and no window where a circle is stuck mid-week.
    /// ponytail: the cutoff is the *device's* local day, so a circle spanning
    /// timezones publishes at each member's own midnight rather than one shared
    /// instant. Fine for a friend group; move to a server-side RPC if a circle
    /// ever spreads far enough that the skew is felt.
    static func liveCutoff(now: Date = .now) -> String { publishDate(for: now) }

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let editionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()
}

/// When an edition closes: the end of Saturday, rolling to next week once
/// passed. A domain rule — the chat renders it as a countdown, and opening a
/// draft stamps its `publish_date` from it, so it can't live in either one.
/// ponytail: hardcoded weekly cadence. Move to a per-circle schedule column
/// when circles want their own rhythm.
enum EditionCountdown {
    static func deadline(after now: Date, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: now)  // 1 = Sunday … 7 = Saturday
        let toSaturday = (7 - weekday + 7) % 7
        let saturday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: toSaturday, to: now)!)
        let deadline = calendar.date(byAdding: .day, value: 1, to: saturday)!
        return deadline > now ? deadline : calendar.date(byAdding: .day, value: 7, to: deadline)!
    }

    /// The Saturday an edition opened now would publish on — the deadline is
    /// the midnight *after* it, so step back a day to name the day itself.
    static func publishDay(after now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -1,
                      to: deadline(after: now, calendar: calendar))!
    }

    /// "August 1" — the edition currently being assembled, named by the Saturday
    /// it closes on. Same day the masthead shows, so compose and the edition
    /// itself can't call the same issue by two different names.
    static func editionName(after now: Date = .now, calendar: Calendar = .current) -> String {
        monthDay.string(from: publishDay(after: now, calendar: calendar))
    }

    /// "Sunday, August 2" — when that edition opens for reading. A week's work
    /// closes Saturday midnight and is readable from Sunday, so this is always
    /// the day AFTER the edition's name. Saying both is the point: authors kept
    /// looking for their submission on the day the edition is named for.
    static func opensOn(after now: Date = .now, calendar: Calendar = .current) -> String {
        weekdayMonthDay.string(from: deadline(after: now, calendar: calendar))
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

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM d"
        return f
    }()
    private static let weekdayMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
}

struct PageMedia: Codable, Identifiable {
    let id: UUID
    let pageId: UUID?
    let mediaUrl: String?     // nil for text widgets
    let mediaType: String?
    let textContent: String?  // nil for media widgets; the @handle for insta cards
    let posterUrl: String?    // insta: storage path of the re-hosted cover frame
    let posterFocus: Double?  // insta: author-chosen vertical crop, 0 top…1 bottom; nil ⇒ center
    let position: Int?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case mediaUrl = "media_url"
        case mediaType = "media_type"
        case textContent = "text_content"
        case posterUrl = "poster_url"
        case posterFocus = "poster_focus"
        case position
        case createdAt = "created_at"
    }
}

struct Page: Codable {
    let id: UUID
    let issueId: UUID?
    let submittedBy: UUID?
    let title: String?        // optional editorial title, shown over the media
    let caption: String?      // optional, set by the author on submit
    var captionStyle: CaptionStyle? = nil  // how the title bar is treated; nil ⇒ default
    var cardShape: CardShape? = nil        // media aspect ratio; nil ⇒ full-bleed (tall)
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case issueId = "issue_id"
        case submittedBy = "submitted_by"
        case title
        case caption
        case captionStyle = "caption_style"
        case cardShape = "card_shape"
        case createdAt = "created_at"
    }
}

struct User: Codable {
    let id: UUID
    let username: String
    let bio: String?
    let avatarUrl: String?
    let role: String?
    let followCredits: Int?
    let circleSlots: Int?
    let isVerified: Bool?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case bio
        case avatarUrl = "avatar_url"
        case role
        case followCredits = "follow_credits"
        case circleSlots = "circle_slots"
        case isVerified = "is_verified"
        case createdAt = "created_at"
    }
}

extension User {
    /// The monogram an avatar falls back to. Two letters from a two-word name,
    /// otherwise the first two characters — "Dave Slater" → DS, "jmoney" → JM.
    /// Lives here because three screens were each keeping their own copy.
    var initials: String {
        let words = username.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(username.prefix(2)).uppercased()
    }

    /// First name only, for the places that address someone rather than label them.
    var firstName: String {
        String(username.split(separator: " ").first ?? Substring(username))
    }
}
