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
