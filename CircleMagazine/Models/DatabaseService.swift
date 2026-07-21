//
//  Supabase.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/16/26.
//

import Foundation
import Observation
import Supabase

enum IssueError: LocalizedError {
  case emptyData
  var errorDescription: String? { "Issues, pages, or pageMedia was empty" }
}

@MainActor
@Observable
final class DatabaseService {
  let supabase = SupabaseClient(
    supabaseURL: Config.supabaseURL,
    supabaseKey: Config.supabaseAnonKey
  )

  // MARK: - Reads

  func queryUsers() async -> [User] {
    do {
      let users: [User] = try await supabase.from("users").select().execute().value
      return users
    } catch {
      print("Users fetch from supabase failed with \(error)")
      fatalError()
    }
  }

  func queryIssues() async {
    do {
      let issues: [Issue] = try await supabase.from("issues").select().execute().value
      print("Fetched \(issues.count) issues:")
      for issue in issues {
        print(issue)
      }
    } catch {
      print("Issues fetch from supabase failed with \(error)")
    }
  }

  /// The current live issue with its pages (ordered) and each page's widgets
  /// (ordered by position). Returns nil when no issue is live.
  /// could be optimzed for multiple async server calls TODO
  func fetchCurrentIssue() async throws -> Magazine {

    let issues: [Issue] = try await supabase.from("issues")
      .select().eq("is_live", value: true)
      .order("created_at", ascending: false).limit(1).execute().value
    guard let issue = issues.first else { throw IssueError.emptyData }

    let pages: [Page] = try await supabase.from("pages")
      .select().eq("issue_id", value: issue.id.uuidString)
      .order("created_at", ascending: true).execute().value
    guard !pages.isEmpty else { throw IssueError.emptyData }

    // One round trip for all media, then group in memory
    let pageIds = pages.map(\.id.uuidString)
    let media: [PageMedia] = try await supabase.from("page_media")
      .select().in("page_id", values: pageIds)
      .order("position", ascending: true).execute().value
    guard !media.isEmpty else { throw IssueError.emptyData }
    let byPage = Dictionary(grouping: media, by: \.pageId)

    // Authors — one round trip for every page's submitter, keyed by id.
    let authorIds = Array(Set(pages.compactMap(\.submittedBy?.uuidString)))
    let authors: [User] = authorIds.isEmpty ? [] : try await supabase.from("users")
      .select().in("id", values: authorIds).execute().value
    let byId = Dictionary(uniqueKeysWithValues: authors.map { ($0.id, $0) })

    let result = pages.map {
      MagazinePage(page: $0, pageMedia: byPage[$0.id] ?? [], author: $0.submittedBy.flatMap { byId[$0] })
    }
    return Magazine(issue: issue, pages: result)
  }

  /// Cheap staleness probe — just the live issue's id, no pages/media.
  func currentIssueId() async throws -> UUID? {
    let issues: [Issue] = try await supabase.from("issues")
      .select().eq("is_live", value: true)
      .order("created_at", ascending: false).limit(1).execute().value
    return issues.first?.id
  }

  /// Circles the user belongs to, each with its full member list (for bubble
  /// size and the sheet's avatar row).
  /// ponytail: loads every member of every circle — fine at friend-group
  /// scale; switch to a count aggregate if circles get big.
  func fetchCircles(memberOf userId: UUID) async throws -> [CircleSummary] {
    let mine: [CircleMember] = try await supabase.from("circle_members")
      .select().eq("user_id", value: userId.uuidString).execute().value
    let circleIds = mine.map(\.circleId.uuidString)
    guard !circleIds.isEmpty else { return [] }

    let circles: [Circle] = try await supabase.from("circles")
      .select().in("id", values: circleIds).execute().value
    let members: [CircleMember] = try await supabase.from("circle_members")
      .select().in("circle_id", values: circleIds).execute().value

    let userIds = Array(Set(members.map(\.userId.uuidString)))
    let users: [User] = userIds.isEmpty ? [] : try await supabase.from("users")
      .select().in("id", values: userIds).execute().value
    let usersById = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
    let membersByCircle = Dictionary(grouping: members, by: \.circleId)

    return circles.map { circle in
      CircleSummary(circle: circle,
                    members: (membersByCircle[circle.id] ?? []).compactMap { usersById[$0.userId] })
    }
  }

  // MARK: - Writes

  /// Creates a video post. For a YouTube URL we look up the real video title via
  /// oEmbed and store it on the page, so the feed can read `pages.title` without
  /// any per-render network calls. Title lookup is best-effort — a failure just
  /// leaves the title nil rather than blocking the post.
  @discardableResult
  func createVideoPost(issueId: UUID, authorId: UUID, videoURL: URL, caption: String?,
                       captionStyle: CaptionStyle, cardShape: CardShape) async throws -> Page {
    var title: String?
    if case .youtube(let id)? = VideoSource(videoURL) {
      title = await YouTubeOEmbed.title(forVideoID: id)
    }
    let page: Page = try await supabase.from("pages")
      .insert(PageInsert(issueId: issueId, submittedBy: authorId, title: title,
                         caption: caption, captionStyle: captionStyle, cardShape: cardShape))
      .select().single().execute().value
    try await supabase.from("page_media")
      .insert(PageMediaInsert(pageId: page.id, mediaUrl: videoURL.absoluteString,
                              mediaType: "video", position: 0))
      .execute()
    return page
  }

    func createCircle(name: String, creatorID: UUID) async throws -> Circle {

        let circle: Circle = try await supabase.from("circles")
            .insert(CircleInsert(name: name, createdBy: creatorID))
            .select().single().execute().value

        // insert first member
        try await supabase.from("circle_members")
            .insert(CircleMember(circleId: circle.id, userId: creatorID, joinedAt: Date()))
            .execute()

        return circle
    }
}

/// Keyless lookup of a YouTube video's public title via the official oEmbed
/// endpoint (no API key, no quota). Used at post-creation to cache the title.
enum YouTubeOEmbed {
  private struct Response: Decodable { let title: String }

  /// The video's title, or nil if it's private/removed or the request fails.
  static func title(forVideoID id: String) async -> String? {
    guard var components = URLComponents(string: "https://www.youtube.com/oembed") else { return nil }
    components.queryItems = [
      URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"),
      URLQueryItem(name: "format", value: "json"),
    ]
    guard let url = components.url else { return nil }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
      return try JSONDecoder().decode(Response.self, from: data).title
    } catch {
      return nil
    }
  }
}

private enum Config {
  private static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

  static let supabaseURL: URL = {
    if isPreview { return URL(string: "https://preview.invalid")! }
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
          let url = URL(string: raw) else {
      fatalError("SUPABASE_URL missing from Info.plist — ensure Config.xcconfig is set in Xcode project configurations")
    }
    return url
  }()

  static let supabaseAnonKey: String = {
    if isPreview { return "preview-key" }
    guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else {
      fatalError("SUPABASE_ANON_KEY missing from Info.plist — ensure Config.xcconfig is set in Xcode project configurations")
    }
    return key
  }()
}
