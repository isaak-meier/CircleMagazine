//
//  AccountManagerTests.swift
//  CircleMagazineTests
//
//  AccountManager's session handling and the email-OTP sign-in flow. Every
//  auth call now goes through DatabaseService, so the spy can drive the whole
//  thing — including the session stream, which the test yields events into by
//  hand rather than waiting on Supabase.
//

import Foundation
import Testing
@testable import CircleMagazine

// MARK: - DB spy

private final class SpyDatabase: DatabaseService, @unchecked Sendable {
    struct Boom: Error, LocalizedError {
        var errorDescription: String? { "invalid login credentials" }
    }

    /// The session stream AccountManager subscribes to in its init. Held so a
    /// test can yield `.restored` / `.signedOut` whenever it likes.
    private let stream: AsyncStream<AuthChange>
    private let continuation: AsyncStream<AuthChange>.Continuation

    /// The profile `currentProfile()` finds. nil ⇒ no profile row yet
    /// (mid-signup); `profileError` ⇒ the lookup throws.
    var profile: User?
    var profileError: Error?
    var userId = UUID()

    var sendOTPError: Error?
    var verifyOTPError: Error?
    var signOutError: Error?
    var createProfileError: Error?

    private(set) var sentCodesTo: [String] = []
    private(set) var verifiedCodes: [(email: String, code: String)] = []
    private(set) var signOutCalls = 0
    private(set) var createdProfiles: [(id: UUID, username: String)] = []
    private(set) var profileLookups = 0

    override init() {
        (stream, continuation) = AsyncStream<AuthChange>.makeStream()
        super.init()
    }

    func emit(_ change: AuthChange) { continuation.yield(change) }

    override func authChanges() -> AsyncStream<AuthChange> { stream }

    override func sendOTP(email: String) async throws {
        sentCodesTo.append(email)
        if let sendOTPError { throw sendOTPError }
    }

    override func verifyOTP(email: String, code: String) async throws {
        verifiedCodes.append((email, code))
        if let verifyOTPError { throw verifyOTPError }
    }

    override func signOut() async throws {
        signOutCalls += 1
        if let signOutError { throw signOutError }
    }

    override func currentUserId() async throws -> UUID { userId }

    override func currentProfile() async throws -> User? {
        profileLookups += 1
        if let profileError { throw profileError }
        return profile
    }

    override func createProfile(userId: UUID, username: String) async throws {
        createdProfiles.append((userId, username))
        if let createProfileError { throw createProfileError }
    }
}

// MARK: - Suite

@Suite(.serialized) @MainActor
struct AccountManagerTests {
    private let spy = SpyDatabase()

    private static func user(_ name: String) -> User {
        User(id: UUID(), username: name, bio: nil, avatarUrl: nil, role: nil,
             followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    }

    private let me = Self.user("You Person")

    private func makeAccount() -> AccountManager { AccountManager(db: spy) }

    private func authLabel(_ state: AccountManager.AuthState) -> String {
        switch state {
        case .loading:  "loading"
        case .signedOut: "signedOut"
        case .signedIn:  "signedIn"
        }
    }

    private func signedInUser(_ state: AccountManager.AuthState) -> User? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    private func stepLabel(_ step: AccountManager.Step) -> String {
        switch step {
        case .email:    "email"
        case .code:     "code"
        case .username: "username"
        }
    }

    /// The listener runs in its own Task, so yield until it has consumed the
    /// event and settled out of `.loading` (bounded, so a bug fails rather
    /// than hangs).
    private func settle(_ account: AccountManager) async {
        for _ in 0..<500 {
            if authLabel(account.authState) != "loading" { return }
            await Task.yield()
        }
    }

    // MARK: - Session restore

    @Test func startsLoadingUntilTheSessionIsKnown() {
        #expect(authLabel(makeAccount().authState) == "loading")
    }

    @Test func noSessionOnLaunchMeansSignedOut() async {
        let account = makeAccount()
        spy.emit(.restored(hasSession: false))
        await settle(account)
        #expect(authLabel(account.authState) == "signedOut")
        #expect(spy.profileLookups == 0)   // nothing to look up
    }

    @Test func aRestoredSessionWithAProfileSignsIn() async {
        spy.profile = me
        let account = makeAccount()
        spy.emit(.restored(hasSession: true))
        await settle(account)
        #expect(authLabel(account.authState) == "signedIn")
        #expect(signedInUser(account.authState)?.id == me.id)
    }

    /// App killed mid-signup: the auth user exists but never picked a username.
    /// Documented behaviour is to fall back to signedOut and re-OTP.
    @Test func aSessionWithNoProfileFallsBackToSignedOut() async {
        spy.profile = nil
        let account = makeAccount()
        spy.emit(.restored(hasSession: true))
        await settle(account)
        #expect(authLabel(account.authState) == "signedOut")
    }

    /// A failed profile lookup is treated the same way — never a stuck spinner.
    @Test func aFailedProfileLookupFallsBackToSignedOut() async {
        spy.profileError = SpyDatabase.Boom()
        let account = makeAccount()
        spy.emit(.restored(hasSession: true))
        await settle(account)
        #expect(authLabel(account.authState) == "signedOut")
    }

    @Test func aSignedOutEventFlipsTheState() async {
        spy.profile = me
        let account = makeAccount()
        spy.emit(.restored(hasSession: true))
        await settle(account)
        #expect(authLabel(account.authState) == "signedIn")

        spy.emit(.signedOut)
        for _ in 0..<500 where authLabel(account.authState) == "signedIn" { await Task.yield() }
        #expect(authLabel(account.authState) == "signedOut")
    }

    // MARK: - signOut

    /// signOut only asks the SDK; the listener is what flips the state, so the
    /// VM must not optimistically sign itself out.
    @Test func signOutDelegatesAndLeavesTheStateToTheListener() async throws {
        spy.profile = me
        let account = makeAccount()
        spy.emit(.restored(hasSession: true))
        await settle(account)
        try await account.signOut()
        #expect(spy.signOutCalls == 1)
        #expect(authLabel(account.authState) == "signedIn")   // until .signedOut arrives
    }

    @Test func signOutRethrows() async {
        spy.signOutError = SpyDatabase.Boom()
        let account = makeAccount()
        await #expect(throws: SpyDatabase.Boom.self) { try await account.signOut() }
    }

    // MARK: - sendCode

    @Test func sendCodeEmailsTheAddressAndAdvancesToTheCodeStep() async {
        let account = makeAccount()
        account.email = "isaak@example.com"
        await account.sendCode()
        #expect(spy.sentCodesTo == ["isaak@example.com"])
        #expect(stepLabel(account.step) == "code")
        #expect(account.errorText == nil)
        #expect(!account.isLoading)
    }

    /// A rejected address must not advance the step, or the user is stranded on
    /// a code screen for an email that never got one.
    @Test func sendCodeFailureStaysOnTheEmailStepWithTheReason() async {
        spy.sendOTPError = SpyDatabase.Boom()
        let account = makeAccount()
        account.email = "nope@example.com"
        await account.sendCode()
        #expect(stepLabel(account.step) == "email")
        #expect(account.errorText == "invalid login credentials")
        #expect(!account.isLoading)
    }

    @Test func resendCodeSendsAgainWithoutChangingTheStep() async {
        let account = makeAccount()
        account.email = "isaak@example.com"
        await account.sendCode()
        await account.resendCode()
        #expect(spy.sentCodesTo.count == 2)
        #expect(stepLabel(account.step) == "code")
    }

    // MARK: - verify

    @Test func verifyPassesTheEmailAndTypedCode() async {
        spy.profile = me
        let account = makeAccount()
        account.email = "isaak@example.com"
        account.code = "123456"
        await account.verify()
        #expect(spy.verifiedCodes.first?.email == "isaak@example.com")
        #expect(spy.verifiedCodes.first?.code == "123456")
    }

    /// A returning user has a profile already — straight in, no username step.
    @Test func verifyWithAnExistingProfileSignsIn() async {
        spy.profile = me
        let account = makeAccount()
        await account.verify()
        #expect(authLabel(account.authState) == "signedIn")
        #expect(signedInUser(account.authState)?.id == me.id)
        #expect(account.errorText == nil)
    }

    /// A brand-new user verified their email but has no profile yet.
    @Test func verifyWithNoProfileAdvancesToTheUsernameStep() async {
        spy.profile = nil
        let account = makeAccount()
        await account.verify()
        #expect(stepLabel(account.step) == "username")
        #expect(authLabel(account.authState) == "loading")   // not signed in yet
    }

    @Test func verifyFailureShowsTheReasonAndHoldsTheStep() async {
        let account = makeAccount()
        await account.sendCode()          // the real way onto the code step
        spy.verifyOTPError = SpyDatabase.Boom()
        account.code = "000000"
        await account.verify()
        #expect(account.errorText == "invalid login credentials")
        #expect(stepLabel(account.step) == "code")   // stays put for a retry
    }

    /// A wrong code is retryable: the second attempt clears the first's error.
    @Test func retryingAfterABadCodeClearsTheError() async {
        spy.verifyOTPError = SpyDatabase.Boom()
        let account = makeAccount()
        await account.verify()
        #expect(account.errorText != nil)

        spy.verifyOTPError = nil
        spy.profile = me
        await account.verify()
        #expect(account.errorText == nil)
        #expect(authLabel(account.authState) == "signedIn")
    }

    // MARK: - createAccount

    @Test func createAccountWritesTheProfileForTheSignedInUserAndSignsIn() async {
        let uid = UUID()
        spy.userId = uid
        spy.profile = me        // the row createProfile just wrote, read back
        let account = makeAccount()
        account.username = "isaak"
        await account.createAccount()

        #expect(spy.createdProfiles.first?.id == uid)
        #expect(spy.createdProfiles.first?.username == "isaak")
        #expect(authLabel(account.authState) == "signedIn")
        #expect(signedInUser(account.authState)?.id == me.id)
    }

    /// The insert succeeded but the row can't be read back — surfaced rather
    /// than leaving the user on a spinner.
    @Test func createAccountSurfacesAMissingProfileAfterTheWrite() async {
        spy.profile = nil
        let account = makeAccount()
        account.username = "isaak"
        await account.createAccount()
        #expect(account.errorText == AccountError.profileMissingAfterCreate.errorDescription)
        #expect(authLabel(account.authState) == "loading")
    }

    @Test func createAccountFailureShowsTheReason() async {
        spy.createProfileError = SpyDatabase.Boom()
        let account = makeAccount()
        account.username = "taken"
        await account.createAccount()
        #expect(account.errorText == "invalid login credentials")
        #expect(authLabel(account.authState) == "loading")
    }

    // MARK: - The shared loading/error wrapper

    @Test func isLoadingIsClearedOnBothSuccessAndFailure() async {
        let account = makeAccount()
        await account.sendCode()
        #expect(!account.isLoading)

        spy.sendOTPError = SpyDatabase.Boom()
        await account.sendCode()
        #expect(!account.isLoading)
    }

    @Test func aSucceedingActionClearsAPreviousError() async {
        spy.sendOTPError = SpyDatabase.Boom()
        let account = makeAccount()
        await account.sendCode()
        #expect(account.errorText != nil)

        spy.sendOTPError = nil
        await account.sendCode()
        #expect(account.errorText == nil)
    }
}
