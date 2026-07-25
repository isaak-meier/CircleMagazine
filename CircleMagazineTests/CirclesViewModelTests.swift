//
//  CirclesViewModelTests.swift
//  CircleMagazineTests
//
//  CirclesViewModel's public surface: the load state machine and the create /
//  join commands that grow a bubble in place. The DB is a subclass spy; the
//  IssueStore is real but fed by the same spy, so `load`'s warm-up is observable
//  as fetch calls rather than mocked away.
//

import Foundation
import Testing
@testable import CircleMagazine

// MARK: - DB spy

private final class SpyDatabase: DatabaseService, @unchecked Sendable {
    struct Boom: Error, LocalizedError {
        var errorDescription: String? { "network is down" }
    }

    /// What fetchCircles returns; nil ⇒ it throws.
    var stubbedCircles: [CircleSummary]?
    var stubbedCreatedCircle: Circle?
    var stubbedJoinedSummary: CircleSummary?

    private(set) var fetchCirclesCalls = 0
    private(set) var createCalls: [(name: String, creator: UUID)] = []
    private(set) var joinCalls: [(code: String, user: UUID)] = []
    /// Circle ids the store asked about while warming — proof the preload ran.
    private(set) var warmedCircleIds: [UUID] = []

    override func fetchCircles(memberOf userId: UUID) async throws -> [CircleSummary] {
        fetchCirclesCalls += 1
        guard let stubbedCircles else { throw Boom() }
        return stubbedCircles
    }

    override func createCircle(name: String, creatorID: UUID) async throws -> Circle {
        createCalls.append((name, creatorID))
        guard let stubbedCreatedCircle else { throw Boom() }
        return stubbedCreatedCircle
    }

    override func joinCircle(code: String, userId: UUID) async throws -> CircleSummary {
        joinCalls.append((code, userId))
        guard let stubbedJoinedSummary else { throw JoinError.badCode }
        return stubbedJoinedSummary
    }

    /// The store's warm-up path bottoms out here. Returning nil keeps each
    /// circle in `.composing` — we only care that it was asked.
    override func fetchCurrentIssue(circleId: UUID) async throws -> Magazine? {
        warmedCircleIds.append(circleId)
        return nil
    }
}

// MARK: - Suite

@MainActor
struct CirclesViewModelTests {
    private let spy = SpyDatabase()
    private let me = User(id: UUID(), username: "You Person", bio: nil, avatarUrl: nil,
                          role: nil, followCredits: nil, circleSlots: nil,
                          isVerified: nil, createdAt: nil)

    private func makeVM() -> CirclesViewModel {
        CirclesViewModel(db: spy, store: IssueStore(db: spy), me: me)
    }

    private func circle(_ name: String) -> CircleSummary {
        CircleSummary(circle: Circle(id: UUID(), name: name, createdBy: me.id,
                                     createdAt: nil, inviteCode: "ABC123"),
                      members: [me])
    }

    /// The loaded list, or nil in any other state — keeps the assertions short.
    private func loadedNames(_ vm: CirclesViewModel) -> [String]? {
        guard case .loaded(let circles) = vm.state else { return nil }
        return circles.map(\.name)
    }

    /// Which case the state is in, as a string. `Issue` is one of this app's own
    /// model types, so Swift Testing's `Issue.record` is out of reach here —
    /// comparing labels keeps the failure output just as readable.
    private func label(_ state: CirclesViewModel.LoadState) -> String {
        switch state {
        case .loading: "loading"
        case .loaded:  "loaded"
        case .failed:  "failed"
        }
    }

    private func failureMessage(_ state: CirclesViewModel.LoadState) -> String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    // MARK: - Initial state

    @Test func startsLoading() {
        #expect(label(makeVM().state) == "loading")
    }

    // MARK: - load

    @Test func loadPublishesTheFetchedCircles() async {
        spy.stubbedCircles = [circle("Dean St."), circle("Book Club")]
        let vm = makeVM()
        await vm.load()
        #expect(loadedNames(vm) == ["Dean St.", "Book Club"])
    }

    @Test func loadOfAnEmptyAccountLoadsAnEmptyList() async {
        spy.stubbedCircles = []
        let vm = makeVM()
        await vm.load()
        #expect(loadedNames(vm) == [])
    }

    @Test func loadFailureCarriesTheUnderlyingReason() async {
        spy.stubbedCircles = nil   // throws
        let vm = makeVM()
        await vm.load()
        #expect(label(vm.state) == "failed")
        #expect(failureMessage(vm.state)?.contains("network is down") == true)
    }

    /// load() is the first-load command: once it has landed, calling it again
    /// (a second onAppear) must not refetch.
    @Test func loadIsIdempotentOnceLoaded() async {
        spy.stubbedCircles = [circle("Dean St.")]
        let vm = makeVM()
        await vm.load()
        await vm.load()
        #expect(spy.fetchCirclesCalls == 1)
    }

    /// A failure is terminal for load() too — the guard only lets `.loading`
    /// through, so retrying needs a fresh VM (or a future explicit retry).
    @Test func loadDoesNotRetryAfterFailure() async {
        spy.stubbedCircles = nil
        let vm = makeVM()
        await vm.load()
        spy.stubbedCircles = [circle("Dean St.")]
        await vm.load()
        #expect(spy.fetchCirclesCalls == 1)
        #expect(label(vm.state) == "failed")
    }

    @Test func loadWarmsEveryCirclesEdition() async {
        let a = circle("Dean St."), b = circle("Book Club")
        spy.stubbedCircles = [a, b]
        await makeVM().load()
        #expect(Set(spy.warmedCircleIds) == Set([a.id, b.id]))
    }

    @Test func loadOfAnEmptyListWarmsNothing() async {
        spy.stubbedCircles = []
        await makeVM().load()
        #expect(spy.warmedCircleIds.isEmpty)
    }

    /// A pre-seeded VM (previews) must not fire a fetch behind the preview's back.
    @Test func loadNoOpsOnAPreSeededState() async {
        let vm = CirclesViewModel.preview(.loaded([]))
        await vm.load()
        #expect(spy.fetchCirclesCalls == 0)
    }

    // MARK: - create

    @Test func createPassesTheNameAndMyIdToTheDB() async throws {
        spy.stubbedCircles = []
        spy.stubbedCreatedCircle = Circle(id: UUID(), name: "New Circle", createdBy: me.id,
                                          createdAt: nil, inviteCode: "NEW123")
        let vm = makeVM()
        await vm.load()
        try await vm.create(named: "New Circle")
        #expect(spy.createCalls.count == 1)
        #expect(spy.createCalls.first?.name == "New Circle")
        #expect(spy.createCalls.first?.creator == me.id)
    }

    @Test func createAppendsTheNewCircleWithMeAsItsOnlyMember() async throws {
        spy.stubbedCircles = [circle("Dean St.")]
        spy.stubbedCreatedCircle = Circle(id: UUID(), name: "New Circle", createdBy: me.id,
                                          createdAt: nil, inviteCode: "NEW123")
        let vm = makeVM()
        await vm.load()
        try await vm.create(named: "New Circle")
        #expect(loadedNames(vm) == ["Dean St.", "New Circle"])
        guard case .loaded(let circles) = vm.state else { return }
        #expect(circles.last?.members.map(\.id) == [me.id])
    }

    @Test func createRethrowsSoTheSheetCanKeepTheTypedName() async {
        spy.stubbedCircles = []
        spy.stubbedCreatedCircle = nil   // throws
        let vm = makeVM()
        await vm.load()
        await #expect(throws: SpyDatabase.Boom.self) { try await vm.create(named: "Doomed") }
        #expect(loadedNames(vm) == [])   // list untouched
    }

    /// Creating before the list has loaded still writes to the DB; there's just
    /// no loaded list to append to, and `load()` will pick it up.
    @Test func createWhileStillLoadingWritesButDoesNotChangeState() async throws {
        spy.stubbedCreatedCircle = Circle(id: UUID(), name: "Early", createdBy: me.id,
                                          createdAt: nil, inviteCode: "EARLY1")
        let vm = makeVM()
        try await vm.create(named: "Early")
        #expect(spy.createCalls.count == 1)
        #expect(label(vm.state) == "loading")
    }

    // MARK: - join

    @Test func joinPassesTheCodeAndMyIdToTheDB() async throws {
        spy.stubbedCircles = []
        spy.stubbedJoinedSummary = circle("Joined")
        let vm = makeVM()
        await vm.load()
        try await vm.join(code: "abc123")
        #expect(spy.joinCalls.first?.code == "abc123")   // DB upper-cases, not the VM
        #expect(spy.joinCalls.first?.user == me.id)
    }

    @Test func joinAppendsTheCircle() async throws {
        spy.stubbedCircles = [circle("Dean St.")]
        spy.stubbedJoinedSummary = circle("Book Club")
        let vm = makeVM()
        await vm.load()
        try await vm.join(code: "ABC123")
        #expect(loadedNames(vm) == ["Dean St.", "Book Club"])
    }

    /// Re-joining somewhere you already belong is a no-op on screen — no
    /// duplicate bubble for the same circle.
    @Test func joiningACircleIAlreadyBelongToDoesNotDuplicateIt() async throws {
        let existing = circle("Dean St.")
        spy.stubbedCircles = [existing]
        spy.stubbedJoinedSummary = existing
        let vm = makeVM()
        await vm.load()
        try await vm.join(code: "ABC123")
        #expect(loadedNames(vm) == ["Dean St."])
    }

    @Test func joinWithABadCodeRethrows() async {
        spy.stubbedCircles = []
        spy.stubbedJoinedSummary = nil   // throws JoinError.badCode
        let vm = makeVM()
        await vm.load()
        await #expect(throws: JoinError.badCode) { try await vm.join(code: "NOPE00") }
        #expect(loadedNames(vm) == [])
    }

    @Test func joinWhileStillLoadingWritesButDoesNotChangeState() async throws {
        spy.stubbedJoinedSummary = circle("Early")
        let vm = makeVM()
        try await vm.join(code: "ABC123")
        #expect(spy.joinCalls.count == 1)
        #expect(label(vm.state) == "loading")
    }

    @Test func joinAfterAFailedLoadLeavesTheFailureVisible() async throws {
        spy.stubbedCircles = nil
        spy.stubbedJoinedSummary = circle("Book Club")
        let vm = makeVM()
        await vm.load()
        try await vm.join(code: "ABC123")
        #expect(label(vm.state) == "failed")
    }
}
