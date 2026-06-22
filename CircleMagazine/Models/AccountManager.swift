//
//  AccountManager.swift
//  CircleMagazine
//
//  Owns the account/session state and the sign-in flow. Same pattern as
//  IssueLoader: @Observable + @MainActor, view-independent, exposes state
//  the views render.
//

import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AccountManager {
  let db: DatabaseService

  enum AuthState { case loading, signedOut, signedIn }
  enum Step { case email, code, username }

  // Session status — the App switches on this, like IssueLoader.loadState.
  private(set) var authState: AuthState = .loading

  // Sign-in flow state (moved out of AuthView).
  private(set) var step: Step = .email
  var email = ""
  var code = ""
  var username = ""
  private(set) var isLoading = false
  private(set) var errorText: String?

  init(db: DatabaseService) {
    self.db = db
    Task { await listen() }
  }

  // MARK: - Session

  private func listen() async {
    for await change in db.supabase.auth.authStateChanges {
      switch change.event {
      case .initialSession: await evaluate(change.session)  // launch / restore
      case .signedOut:      authState = .signedOut
      default: break  // .signedIn is driven explicitly by the flow below
      }
    }
  }

  private func evaluate(_ session: Session?) async {
    guard session != nil else { authState = .signedOut; return }
    // ponytail: session-but-no-profile (app killed mid-signup) falls back to signedOut → re-OTP. Rare; add a .needsProfile state if it bites.
    authState = ((try? await hasProfile()) ?? false) ? .signedIn : .signedOut
  }

  private func hasProfile() async throws -> Bool {
    let uid = try await db.supabase.auth.session.user.id
    let rows: [User] = try await db.supabase.from("users")
      .select().eq("id", value: uid.uuidString).limit(1).execute().value
    return !rows.isEmpty
  }

  func signOut() async throws {
    try await db.supabase.auth.signOut()  // listener flips authState to .signedOut
  }

  // MARK: - Sign-in flow

  func sendCode() async {
    await run {
      try await self.db.supabase.auth.signInWithOTP(email: self.email)  // shouldCreateUser defaults true
      self.step = .code
    }
  }

  func resendCode() async {
    await run { try await self.db.supabase.auth.signInWithOTP(email: self.email) }
  }

  func verify() async {
    await run {
      try await self.db.supabase.auth.verifyOTP(email: self.email, token: self.code, type: .email)
      if try await self.hasProfile() { self.authState = .signedIn } else { self.step = .username }
    }
  }

  func createAccount() async {
    await run {
      let userId = try await self.db.supabase.auth.session.user.id
      try await self.db.supabase.from("users").insert(UserInsert(id: userId, username: self.username)).execute()
      self.authState = .signedIn
    }
  }

  /// Shared isLoading/error wrapper for the flow actions.
  private func run(_ action: () async throws -> Void) async {
    isLoading = true
    errorText = nil
    do { try await action() } catch { errorText = error.localizedDescription }
    isLoading = false
  }
}
