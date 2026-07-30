//
//  SubmissionEditionTests.swift
//  CircleMagazineTests
//
//  DatabaseService.issueIdForSubmission — which edition a new post lands in.
//  Three outcomes plus a race: the live issue, an already-open draft, a draft
//  this call opens, and the branch where another member opened one first.
//
//  Only the orchestration is under test; the three steps it composes are
//  overridden, since each is a single Supabase round trip.
//

import Foundation
import Testing
@testable import CircleMagazine

// MARK: - DB spy

/// Stubs the three lookups `issueIdForSubmission` composes, and counts them so
/// the tests can prove which path was taken.
private final class SpyDatabase: DatabaseService, @unchecked Sendable {
    struct Rejected: Error, LocalizedError {
        var errorDescription: String? { "duplicate key value violates unique constraint" }
    }

    var liveIssueId: UUID?
    /// Answers for successive `draftIssueId` calls — the race test needs the
    /// second call to differ from the first.
    var draftAnswers: [UUID?] = [nil]
    var createdDraftId: UUID?
    /// Set to make `createDraftIssue` throw, as the one-draft index would.
    var createError: Error?

    private(set) var liveCalls = 0
    private(set) var draftCalls = 0
    private(set) var createCalls: [UUID] = []

    override func currentIssueId(circleId: UUID) async throws -> UUID? {
        liveCalls += 1
        return liveIssueId
    }

    override func draftIssueId(circleId: UUID) async throws -> UUID? {
        defer { draftCalls += 1 }
        return draftCalls < draftAnswers.count ? draftAnswers[draftCalls] : draftAnswers.last ?? nil
    }

    override func createDraftIssue(circleId: UUID) async throws -> UUID {
        createCalls.append(circleId)
        if let createError { throw createError }
        return createdDraftId ?? UUID()
    }
}

// MARK: - Suite

@Suite(.serialized) @MainActor
struct SubmissionEditionTests {
    private let spy = SpyDatabase()
    private let circleId = UUID()

    // MARK: - The live edition is never written into

    /// A published issue is finished. Posting while one is live means "next
    /// week", so the submission goes to the draft — never into the edition the
    /// circle is currently reading.
    ///
    /// This is load-bearing under derived liveness: after week one there is
    /// ALWAYS a live edition, so a lookup that preferred it would swallow every
    /// submission forever and no second draft would ever be created.
    @Test func aLiveEditionIsNeverTheSubmissionTarget() async throws {
        let live = UUID(), draft = UUID()
        spy.liveIssueId = live
        spy.draftAnswers = [draft]
        #expect(try await spy.issueIdForSubmission(circleId: circleId) == draft)
        #expect(spy.liveCalls == 0)        // doesn't even ask what's live
    }

    /// Same, with no draft open yet: it opens one rather than falling back to
    /// the live edition.
    @Test func aLiveEditionDoesNotPreventOpeningTheNextDraft() async throws {
        let live = UUID(), created = UUID()
        spy.liveIssueId = live
        spy.draftAnswers = [nil]
        spy.createdDraftId = created
        #expect(try await spy.issueIdForSubmission(circleId: circleId) == created)
        #expect(spy.createCalls == [circleId])
    }

    // MARK: - An open draft is reused

    /// The second and later submissions of the compose phase.
    @Test func anOpenDraftIsReused() async throws {
        let draft = UUID()
        spy.liveIssueId = nil
        spy.draftAnswers = [draft]
        #expect(try await spy.issueIdForSubmission(circleId: circleId) == draft)
        #expect(spy.createCalls.isEmpty)   // nothing new opened
    }

    // MARK: - The first submission opens a draft

    /// The compose phase's first post of the week: nothing live, no draft yet.
    @Test func theFirstSubmissionOfTheWeekOpensADraft() async throws {
        let created = UUID()
        spy.liveIssueId = nil
        spy.draftAnswers = [nil]
        spy.createdDraftId = created
        #expect(try await spy.issueIdForSubmission(circleId: circleId) == created)
        #expect(spy.createCalls == [circleId])
    }

    @Test func openingADraftIsTriedOnlyAfterTheDraftLookupMisses() async throws {
        spy.liveIssueId = nil
        spy.draftAnswers = [nil]
        spy.createdDraftId = UUID()
        _ = try await spy.issueIdForSubmission(circleId: circleId)
        #expect(spy.liveCalls == 0)
        #expect(spy.draftCalls == 1)
        #expect(spy.createCalls.count == 1)
    }

    // MARK: - Losing the race

    /// Two members hit Post in the same second. The one-draft-per-circle index
    /// rejects the loser's insert; it must fall into the winner's draft rather
    /// than surfacing a duplicate-key error to the author.
    @Test func losingTheRaceFallsIntoTheWinnersDraft() async throws {
        let winners = UUID()
        spy.liveIssueId = nil
        spy.draftAnswers = [nil, winners]      // empty on first look, theirs on re-read
        spy.createError = SpyDatabase.Rejected()
        #expect(try await spy.issueIdForSubmission(circleId: circleId) == winners)
        #expect(spy.draftCalls == 2)           // looked again after the rejection
    }

    /// If the insert failed for some reason *other* than the race, the re-read
    /// finds nothing and the original error surfaces — no silent swallow.
    @Test func aRealInsertFailureIsRethrown() async {
        spy.liveIssueId = nil
        spy.draftAnswers = [nil, nil]          // still nothing on the second look
        spy.createError = SpyDatabase.Rejected()
        await #expect(throws: SpyDatabase.Rejected.self) {
            try await self.spy.issueIdForSubmission(circleId: self.circleId)
        }
    }

    // MARK: - The date a draft is stamped with

    /// A draft's publish_date is the Saturday it closes on — the same day the
    /// chat's countdown runs to. Checked here because `createDraftIssue` is the
    /// only writer of that column.
    /// Local calendar throughout: `Issue.publishDate` formats in the local zone,
    /// so pinning the input to UTC here would fail everywhere except UTC.
    @Test func aDraftIsStampedWithTheSaturdayItCloses() {
        let calendar = Calendar.current
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1,
                                                          hour: 12))!
        let saturday = EditionCountdown.publishDay(after: wednesday, calendar: calendar)
        #expect(Issue.publishDate(for: saturday) == "2026-07-04")
    }
}
