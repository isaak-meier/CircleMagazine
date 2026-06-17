//
//  Supabase.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/16/26.
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class DatabaseService {
  let supabase = SupabaseClient(
    supabaseURL: Config.supabaseURL,
    supabaseKey: Config.supabaseAnonKey
  )

  // MARK: - Session

  enum AuthState { case loading, signedOut, signedIn }
  var authState: AuthState = .loading

  init() {
    Task {
      for await change in supabase.auth.authStateChanges {
        switch change.event {
        case .initialSession: await evaluate(change.session)  // launch / restore
        case .signedOut:      authState = .signedOut
        default: break  // .signedIn is driven explicitly by AuthView
        }
      }
    }
  }

  private func evaluate(_ session: Session?) async {
    guard session != nil else { authState = .signedOut; return }
    // ponytail: session-but-no-profile (app killed mid-signup) falls back to signedOut → re-OTP. Rare; add a .needsProfile state if it bites.
    authState = ((try? await hasProfile()) ?? false) ? .signedIn : .signedOut
  }

  func hasProfile() async throws -> Bool {
    let uid = try await supabase.auth.session.user.id
    let rows: [User] = try await supabase.from("users")
      .select().eq("id", value: uid.uuidString).limit(1).execute().value
    return !rows.isEmpty
  }

  func signOut() async throws { try await supabase.auth.signOut() }

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

  // MARK: - Auth

  func sendOTP(email: String) async throws {
    try await supabase.auth.signInWithOTP(email: email)  // shouldCreateUser defaults true
  }

  func verifyOTP(email: String, code: String) async throws {
    try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
  }

  func createProfile(username: String) async throws {
    let userId = try await supabase.auth.session.user.id
    try await supabase.from("users").insert(UserInsert(id: userId, username: username)).execute()
  }

  // MARK: - Writes

  @discardableResult
  func insertTestIssue() async -> Bool {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    let today = formatter.string(from: Date())

    let testIssue = IssueInsert(publishDate: today, isLive: false)
    do {
      try await supabase.from("issues").insert(testIssue).execute()
      return true
    } catch {
      print("Test issue insert failed with \(error)")
      return false
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
