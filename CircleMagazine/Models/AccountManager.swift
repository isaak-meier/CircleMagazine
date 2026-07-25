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

enum AccountError: LocalizedError {
  case profileMissingAfterCreate
  var errorDescription: String? { "Account was created but its profile could not be loaded" }
}

@Observable
@MainActor
final class AccountManager {
  let db: DatabaseService

  enum AuthState { case loading, signedOut, signedIn(User) }
  enum Step { case email, code, username }

  // Session status — the App switches on this, like IssueLoader.loadState.
  // .signedIn carries the user's profile row.
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
    for await change in db.authChanges() {
      switch change {
      case .restored(let hasSession): await evaluate(hasSession: hasSession)
      case .signedOut:                authState = .signedOut
      }
    }
  }

  private func evaluate(hasSession: Bool) async {
    guard hasSession else { authState = .signedOut; return }
    // ponytail: session-but-no-profile (app killed mid-signup) falls back to signedOut → re-OTP. Rare; add a .needsProfile state if it bites.
    if let user = try? await db.currentProfile() { authState = .signedIn(user) }
    else { authState = .signedOut }
  }

  func signOut() async throws {
    try await db.signOut()  // listener flips authState to .signedOut
  }

  // MARK: - Sign-in flow

  func sendCode() async {
    await run {
      try await self.db.sendOTP(email: self.email)
      self.step = .code
    }
  }

  func resendCode() async {
    await run { try await self.db.sendOTP(email: self.email) }
  }

  func verify() async {
    await run {
      try await self.db.verifyOTP(email: self.email, code: self.code)
      if let user = try await self.db.currentProfile() { self.authState = .signedIn(user) }
      else { self.step = .username }
    }
  }

  func createAccount() async {
    await run {
      let userId = try await self.db.currentUserId()
      try await self.db.createProfile(userId: userId, username: self.username)
      guard let user = try await self.db.currentProfile() else { throw AccountError.profileMissingAfterCreate }
      self.authState = .signedIn(user)
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
