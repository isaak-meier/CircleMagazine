//
//  IssueStoreTests.swift
//  CircleMagazineTests
//
//  The shared edition cache: what warm preloads, what it skips, and what
//  survives a sign-out. The store outlives every ViewModel, so the cache-
//  clearing path is the one that keeps one account's editions out of the next
//  session.
//

import Foundation
import Testing
@testable import CircleMagazine

// MARK: - DB spy

private final class SpyDatabase: DatabaseService, @unchecked Sendable {
    struct Boom: Error, LocalizedError {
        var errorDescription: String? { "network is down" }
    }

    /// Per-circle answers. A circle that's absent resolves to nil (compose
    /// phase); `throwingCircles` makes the fetch throw instead.
    var magazines: [UUID: Magazine] = [:]
    var throwingCircles: Set<UUID> = []
    /// Runs at the top of each fetch — lets a test act while one is suspended.
    var onFetch: (@Sendable (UUID) async -> Void)?

    private(set) var fetchCalls: [UUID] = []

    override func fetchCurrentIssue(circleId: UUID) async throws -> Magazine? {
        await onFetch?(circleId)
        fetchCalls.append(circleId)
        if throwingCircles.contains(circleId) { throw Boom() }
        return magazines[circleId]
    }
}

// MARK: - Suite

@Suite(.serialized) @MainActor
struct IssueStoreTests {
    private let spy = SpyDatabase()

    private func makeStore() -> IssueStore { IssueStore(db: spy) }

    private func magazine(circleId: UUID) -> Magazine {
        Magazine(issue: Issue(id: UUID(), circleId: circleId, publishDate: "2026-07-25",
                              isLive: true, createdAt: nil),
                 pages: [])
    }

    /// Which case the state is in. `Issue` is one of the app's own model types,
    /// so Swift Testing's `Issue.record` is out of reach — labels read as well.
    private func label(_ state: IssueLoadState) -> String {
        switch state {
        case .loading:      "loading"
        case .loaded:       "loaded"
        case .composing:    "composing"
        case .failedToLoad: "failed"
        }
    }

    // MARK: - warm

    @Test func warmPreloadsEveryCircleItIsGiven() async {
        let a = UUID(), b = UUID()
        spy.magazines = [a: magazine(circleId: a), b: magazine(circleId: b)]
        let store = makeStore()
        await store.warm(circleIds: [a, b])
        #expect(label(store.state(for: a)) == "loaded")
        #expect(label(store.state(for: b)) == "loaded")
    }

    @Test func warmingNothingFetchesNothing() async {
        await makeStore().warm(circleIds: [])
        #expect(spy.fetchCalls.isEmpty)
    }

    /// A circle with no live edition warms into the compose phase, not a failure.
    @Test func warmCachesTheComposePhaseToo() async {
        let id = UUID()
        let store = makeStore()
        await store.warm(circleIds: [id])   // no stub ⇒ nil ⇒ composing
        #expect(label(store.state(for: id)) == "composing")
    }

    /// One circle failing must not cost the others their preload.
    @Test func oneFailureDoesNotStopTheRest() async {
        let bad = UUID(), good = UUID()
        spy.throwingCircles = [bad]
        spy.magazines = [good: magazine(circleId: good)]
        let store = makeStore()
        await store.warm(circleIds: [bad, good])
        #expect(label(store.state(for: bad)) == "failed")
        #expect(label(store.state(for: good)) == "loaded")
    }

    /// warm composes `load`, which is idempotent — re-warming an already-cached
    /// circle spends nothing. This is exactly why a stale cache has to be
    /// cleared rather than warmed over.
    @Test func warmingAnAlreadyLoadedCircleIsFree() async {
        let id = UUID()
        spy.magazines = [id: magazine(circleId: id)]
        let store = makeStore()
        await store.warm(circleIds: [id])
        await store.warm(circleIds: [id])
        #expect(spy.fetchCalls == [id])
    }

    /// …but only `.loaded` is idempotent. A circle stuck on compose or a failure
    /// gets another try, so a transient outage isn't cached forever.
    @Test func warmingRetriesCirclesThatNeverLoaded() async {
        let id = UUID()
        spy.throwingCircles = [id]
        let store = makeStore()
        await store.warm(circleIds: [id])
        spy.throwingCircles = []
        spy.magazines = [id: magazine(circleId: id)]
        await store.warm(circleIds: [id])
        #expect(label(store.state(for: id)) == "loaded")
    }

    // MARK: - Sign-out clears the cache

    @Test func invalidateAllDropsEveryCachedEdition() async {
        let a = UUID(), b = UUID()
        spy.magazines = [a: magazine(circleId: a), b: magazine(circleId: b)]
        let store = makeStore()
        await store.warm(circleIds: [a, b])
        store.invalidateAll()
        #expect(label(store.state(for: a)) == "loading")
        #expect(label(store.state(for: b)) == "loading")
    }

    /// The sign-out → sign-in path. Without the clear, warm would no-op on
    /// every circle and the new session would read the old account's editions.
    @Test func warmAfterAClearRefetchesFromScratch() async {
        let id = UUID()
        spy.magazines = [id: magazine(circleId: id)]
        let store = makeStore()
        await store.warm(circleIds: [id])
        store.invalidateAll()
        await store.warm(circleIds: [id])
        #expect(spy.fetchCalls == [id, id])
        #expect(label(store.state(for: id)) == "loaded")
    }

    /// Signing out cancels the warm SwiftUI started, but fetches already in
    /// flight still return. Their results must be dropped, or they'd land in the
    /// cache just after it was cleared.
    @Test func aCancelledWarmDoesNotWriteBackAfterTheClear() async {
        let id = UUID()
        spy.magazines = [id: magazine(circleId: id)]
        let store = makeStore()

        // Sign-out happens while the fetch is suspended: the task is cancelled
        // and the cache cleared before the magazine comes back.
        let warming = Task { await store.warm(circleIds: [id]) }
        spy.onFetch = { @Sendable _ in
            warming.cancel()
            await MainActor.run { store.invalidateAll() }
        }
        await warming.value

        #expect(label(store.state(for: id)) == "loading")   // not the old edition
    }

    // MARK: - state(for:)

    @Test func anUnknownCircleReadsAsLoadingNotAsAFailure() {
        #expect(label(makeStore().state(for: UUID())) == "loading")
    }

    @Test func seededCircleIdsStartOutLoading() {
        let id = UUID()
        #expect(label(IssueStore(db: spy, circleIds: [id]).state(for: id)) == "loading")
    }
}
