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

    enum CodingKeys: String, CodingKey {
        case issueId = "issue_id"
        case submittedBy = "submitted_by"
        case title
        case caption
    }
}

struct PageMediaInsert: Encodable {
    let pageId: UUID
    let mediaUrl: String?
    let mediaType: String?
    let position: Int

    enum CodingKeys: String, CodingKey {
        case pageId = "page_id"
        case mediaUrl = "media_url"
        case mediaType = "media_type"
        case position
    }
}
