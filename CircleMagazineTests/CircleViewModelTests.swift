//
//  CircleViewModelTests.swift
//  CircleMagazineTests
//
//  CircleViewModel's public surface — the identity accessors the chrome reads,
//  the editor check, and the submitters set — plus ViewModelFactory's assembly,
//  since the factory is what guarantees a circle's two phase VMs share one
//  cache.
//

import Foundation
import Testing
@testable import CircleMagazine

// MARK: - DB spy

private final class SpyDatabase: DatabaseService, @unchecked Sendable {
    struct Boom: Error {}

    /// What submitterIds resolves to; nil ⇒ it throws.
    var stubbedSubmitters: Set<UUID>?
    private(set) var submitterCalls: [(memberIds: [UUID], circleId: UUID)] = []

    override func submitterIds(among memberIds: [UUID], circleId: UUID) async throws -> Set<UUID> {
        submitterCalls.append((memberIds, circleId))
        guard let stubbedSubmitters else { throw Boom() }
        return stubbedSubmitters
    }

    override func fetchCurrentIssue(circleId: UUID) async throws -> Magazine? { nil }
}

// MARK: - Suite

/// Serialized, and the debug override is cleared up front: `IssueViewModel`
/// reads `forceComposePhase` out of shared UserDefaults, so a stray value from
/// another suite would report the wrong phase here.
@Suite(.serialized) @MainActor
struct CircleViewModelTests {
    private let spy = SpyDatabase()

    init() {
        UserDefaults.standard.removeObject(forKey: IssueViewModel.forceComposeKey)
    }

    private static func user(_ name: String) -> User {
        User(id: UUID(), username: name, bio: nil, avatarUrl: nil, role: nil,
             followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    }

    private let me = Self.user("You Person")
    private let dave = Self.user("Dave Slater")

    private func summary(name: String? = "Dean St.", createdBy: UUID?,
                         members: [User]) -> CircleSummary {
        CircleSummary(circle: Circle(id: UUID(), name: name, createdBy: createdBy,
                                     createdAt: nil, inviteCode: "ABC123"),
                      members: members)
    }

    private func makeVM(_ summary: CircleSummary) -> CircleViewModel {
        let store = IssueStore(db: spy)
        return CircleViewModel(
            summary: summary, db: spy, me: me,
            issue: IssueViewModel(store: store, circleId: summary.circle.id, me: me),
            chat: ChatViewModel(db: spy, summary: summary, me: me))
    }

    /// The default: a circle I created, with Dave in it.
    private func myCircle() -> CircleViewModel {
        makeVM(summary(createdBy: me.id, members: [me, dave]))
    }

    // MARK: - Identity

    @Test func circleIdIsTheUnderlyingCirclesId() {
        let summary = summary(createdBy: me.id, members: [me])
        #expect(makeVM(summary).circleId == summary.circle.id)
    }

    @Test func nameIsTheCirclesName() {
        #expect(myCircle().name == "Dean St.")
    }

    /// `name` is nullable in the DB; the summary substitutes a placeholder so the
    /// masthead is never blank.
    @Test func nameFallsBackToUntitledWhenTheDBHasNoName() {
        #expect(makeVM(summary(name: nil, createdBy: me.id, members: [me])).name == "Untitled")
    }

    @Test func membersAreTheRosterInOrder() {
        #expect(myCircle().members.map(\.username) == ["You Person", "Dave Slater"])
    }

    @Test func membersCanBeEmpty() {
        #expect(makeVM(summary(createdBy: nil, members: [])).members.isEmpty)
    }

    @Test func inviteCodeIsTheCirclesCode() {
        #expect(myCircle().inviteCode == "ABC123")
    }

    @Test func editorIdIsTheCreator() {
        #expect(myCircle().editorId == me.id)
    }

    @Test func editorIdIsNilForACircleWithNoRecordedCreator() {
        #expect(makeVM(summary(createdBy: nil, members: [me])).editorId == nil)
    }

    // MARK: - isEditor

    @Test func iAmTheEditorOfACircleICreated() {
        #expect(myCircle().isEditor)
    }

    @Test func iAmNotTheEditorOfSomeoneElsesCircle() {
        #expect(!makeVM(summary(createdBy: dave.id, members: [me, dave])).isEditor)
    }

    /// No creator on record means nobody passes the check — including me.
    @Test func nobodyIsEditorWhenTheCreatorIsUnknown() {
        #expect(!makeVM(summary(createdBy: nil, members: [me])).isEditor)
    }

    // MARK: - Submitters

    @Test func submittersStartEmptyBeforeLoading() {
        #expect(myCircle().submitters.isEmpty)
    }

    @Test func loadSubmittersPublishesWhoHasContributed() async {
        spy.stubbedSubmitters = [dave.id]
        let vm = myCircle()
        await vm.loadSubmitters()
        #expect(vm.submitters == [dave.id])
    }

    @Test func loadSubmittersAsksAboutEveryMemberOfThisCircle() async {
        spy.stubbedSubmitters = []
        let vm = myCircle()
        await vm.loadSubmitters()
        let call = try! #require(spy.submitterCalls.first)
        #expect(Set(call.memberIds) == Set([me.id, dave.id]))
        #expect(call.circleId == vm.circleId)
    }

    /// An edition where nobody has posted yet is a normal state, not a failure.
    @Test func loadSubmittersHandlesNobodyHavingSubmitted() async {
        spy.stubbedSubmitters = []
        let vm = myCircle()
        await vm.loadSubmitters()
        #expect(vm.submitters.isEmpty)
    }

    /// A failed lookup degrades to "nobody submitted" rather than blocking the
    /// roster — the sheet still lists every member.
    @Test func loadSubmittersFailureLeavesTheSetEmpty() async {
        spy.stubbedSubmitters = nil   // throws
        let vm = myCircle()
        await vm.loadSubmitters()
        #expect(vm.submitters.isEmpty)
    }

    /// A second load replaces the set — it doesn't accumulate stale ids.
    @Test func loadSubmittersReplacesRatherThanAccumulates() async {
        spy.stubbedSubmitters = [dave.id]
        let vm = myCircle()
        await vm.loadSubmitters()
        spy.stubbedSubmitters = [me.id]
        await vm.loadSubmitters()
        #expect(vm.submitters == [me.id])
    }

    /// And a failure after a success clears it, rather than leaving stale data
    /// that says someone contributed to an edition we can no longer read.
    @Test func loadSubmittersFailureAfterSuccessClearsTheSet() async {
        spy.stubbedSubmitters = [dave.id]
        let vm = myCircle()
        await vm.loadSubmitters()
        spy.stubbedSubmitters = nil
        await vm.loadSubmitters()
        #expect(vm.submitters.isEmpty)
    }

    @Test func loadSubmittersOnAnEmptyRosterAsksWithNoMemberIds() async {
        spy.stubbedSubmitters = []
        await makeVM(summary(createdBy: nil, members: [])).loadSubmitters()
        #expect(spy.submitterCalls.first?.memberIds.isEmpty == true)
    }

    // MARK: - Factory assembly

    @Test func factoryWiresBothPhaseVMsToTheSameCircle() {
        let summary = summary(createdBy: me.id, members: [me, dave])
        let vm = ViewModelFactory(db: spy).makeCircleVM(summary, me: me)
        #expect(vm.circleId == summary.circle.id)
        #expect(vm.issue.circleId == summary.circle.id)
        #expect(vm.chat.circleName == "Dean St.")   // chat got the same summary
        #expect(vm.me.id == me.id)
        #expect(vm.issue.me.id == me.id)
    }

    /// The factory owns one IssueStore for the whole app, so two circles' edition
    /// VMs share a cache. If they didn't, entering a circle twice would refetch.
    @Test func factorySharesOneEditionCacheAcrossCircles() async {
        let factory = ViewModelFactory(db: spy)
        let a = summary(createdBy: me.id, members: [me])
        let first = factory.makeCircleVM(a, me: me)
        await first.issue.refresh()          // caches circle a as .composing

        let second = factory.makeCircleVM(a, me: me)   // same circle, new VM
        #expect(phase(second.issue.state) == "composing")
    }

    /// A circle the shared store has never fetched reads as loading, not as a
    /// phase or a failure.
    @Test func factoryVMForAnUnfetchedCircleStartsLoading() {
        let factory = ViewModelFactory(db: spy)
        let vm = factory.makeCircleVM(summary(createdBy: me.id, members: [me]), me: me)
        #expect(phase(vm.issue.state) == "loading")
    }

    private func phase(_ state: IssueLoadState) -> String {
        switch state {
        case .loading:      "loading"
        case .loaded:       "loaded"
        case .composing:    "composing"
        case .failedToLoad: "failed"
        }
    }
}
