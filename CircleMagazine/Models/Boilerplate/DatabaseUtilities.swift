import Foundation

struct UserInsert: Encodable {
    let id: UUID
    let username: String
}

struct PageInsert: Encodable {
    let issueId: UUID?
    let submittedBy: UUID?
    let title: String?
    let caption: String?
    let captionStyle: CaptionStyle

    enum CodingKeys: String, CodingKey {
        case issueId = "issue_id"
        case submittedBy = "submitted_by"
        case title
        case caption
        case captionStyle = "caption_style"
    }
}

/// A new draft edition. `is_live` is omitted on purpose — the column defaults
/// to false, and only publishing flips it.
struct IssueInsert: Encodable {
    let circleId: UUID
    let publishDate: String

    enum CodingKeys: String, CodingKey {
        case circleId = "circle_id"
        case publishDate = "publish_date"
    }
}

struct CircleInsert: Encodable {
    let name: String
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case name
        case createdBy = "created_by"
    }
}

struct CommentInsert: Encodable {
    let pageId: UUID
    let userId: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case pageId = "page_id"
        case userId = "user_id"
        case body
    }
}

struct ReactionInsert: Encodable {
    let pageId: UUID
    let userId: UUID
    let mediaPath: String

    enum CodingKeys: String, CodingKey {
        case pageId = "page_id"
        case userId = "user_id"
        case mediaPath = "media_path"
    }
}

struct PageMediaInsert: Encodable {
    let pageId: UUID
    let mediaUrl: String?
    let mediaType: String?
    var textContent: String? = nil   // insta: the @handle
    var posterUrl: String? = nil      // insta: storage path of the cover frame
    var posterFocus: Double? = nil    // insta: author-chosen vertical crop, 0…1
    let position: Int

    enum CodingKeys: String, CodingKey {
        case pageId = "page_id"
        case mediaUrl = "media_url"
        case mediaType = "media_type"
        case textContent = "text_content"
        case posterUrl = "poster_url"
        case posterFocus = "poster_focus"
        case position
    }
}
