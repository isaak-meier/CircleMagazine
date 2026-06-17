import Foundation

struct UserInsert: Encodable {
    let id: UUID
    let username: String
}

struct IssueInsert: Encodable {
    let publishDate: String
    let isLive: Bool

    // PostgREST does not auto-convert to snake_case, so map columns explicitly.
    enum CodingKeys: String, CodingKey {
        case publishDate = "publish_date"
        case isLive = "is_live"
    }
}
