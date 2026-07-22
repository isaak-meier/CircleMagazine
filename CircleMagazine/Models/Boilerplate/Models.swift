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
    let publishDate: String
    let isLive: Bool?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
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

struct PageMedia: Codable, Identifiable {
    let id: UUID
    let pageId: UUID?
    let mediaUrl: String?     // nil for text widgets
    let mediaType: String?
    let textContent: String?  // nil for media widgets
    let position: Int?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case mediaUrl = "media_url"
        case mediaType = "media_type"
        case textContent = "text_content"
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
