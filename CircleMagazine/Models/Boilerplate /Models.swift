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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
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

struct PageMedia: Codable {
    let id: UUID
    let pageId: UUID?
    let mediaUrl: String
    let mediaType: String?
    let position: Int?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case mediaUrl = "media_url"
        case mediaType = "media_type"
        case position
        case createdAt = "created_at"
    }
}

struct Page: Codable {
    let id: UUID
    let issueId: UUID?
    let submittedBy: UUID?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case issueId = "issue_id"
        case submittedBy = "submitted_by"
        case createdAt = "created_at"
    }
}

struct User: Codable {
    let id: UUID
    let username: String
    let avatarUrl: String?
    let role: String?
    let followCredits: Int?
    let circleSlots: Int?
    let isVerified: Bool?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case avatarUrl = "avatar_url"
        case role
        case followCredits = "follow_credits"
        case circleSlots = "circle_slots"
        case isVerified = "is_verified"
        case createdAt = "created_at"
    }
}
