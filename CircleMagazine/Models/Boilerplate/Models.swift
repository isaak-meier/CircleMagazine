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

/// The widget kinds a page can hold. Backed by `page_media.media_type`.
enum WidgetType: String {
    case text, image, video, audio
}

extension PageMedia {
    var widgetType: WidgetType? { mediaType.flatMap(WidgetType.init(rawValue:)) }

    /// Render-ready view model for a widget, derived from its DB row.
    /// One case per `WidgetType`; the views render straight from this. Returns
    /// nil when the row is malformed (e.g. an image with no URL).
    var widgetContent: WidgetContent? { WidgetContent(self) }
}

enum WidgetContent {
    case text(String)
    case image(URL)
    case video(URL)
    case audio(URL)

    init?(_ media: PageMedia) {
        switch media.widgetType {
        case .text:
            guard let t = media.textContent else { return nil }
            self = .text(t)
        case .image, .video, .audio:
            guard let raw = media.mediaUrl, let url = URL(string: raw) else { return nil }
            switch media.widgetType {
            case .image: self = .image(url)
            case .video: self = .video(url)
            default:     self = .audio(url)
            }
        case nil:
            return nil
        }
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
