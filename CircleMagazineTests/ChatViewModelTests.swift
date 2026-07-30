//
//  ChatViewModelTests.swift
//  CircleMagazineTests
//
//  ChatViewModel's whole public surface — the strings the header and edition
//  strip show, the rows the thread renders, and the send command. Everything
//  here is pure derivation from (summary, me, messages), so no stubs are needed
//  beyond a DatabaseService the VM never calls.
//

import Foundation
import Testing
@testable import CircleMagazine

@MainActor
struct ChatViewModelTests {

    // MARK: Fixtures

    /// Members are built in a fixed order because `avatarIndex` is that order —
    /// dave is 0, arnell 1, sawyer 2, me 3.
    private let dave = Self.user("Dave Slater")
    private let arnell = Self.user("Arnell Reeves")
    private let sawyer = Self.user("Sawyer W")
    private let me = Self.user("You Person")

    private static func user(_ name: String) -> User {
        User(id: UUID(), username: name, bio: nil, avatarUrl: nil, role: nil,
             followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    }

    /// A circle whose members are exactly `members`, created by `createdBy`.
    private func summary(_ members: [User], createdBy: UUID?, name: String = "Dean St.")
    -> CircleSummary {
        CircleSummary(
            circle: Circle(id: UUID(), name: name, createdBy: createdBy, createdAt: nil,
                           inviteCode: "ABC123"),
            members: members)
    }

    /// The default four-member circle, with arnell as its creator/editor.
    private func vm(_ seed: [ChatMessage] = [], me overrideMe: User? = nil) -> ChatViewModel {
        ChatViewModel(db: DatabaseService(),
                      summary: summary([dave, arnell, sawyer, me], createdBy: arnell.id),
                      me: overrideMe ?? me, seed: seed)
    }

    private func text(_ author: User, _ body: String, at sentAt: Date = .now) -> ChatMessage {
        ChatMessage(author: author, kind: .text(body), sentAt: sentAt)
    }

    private func submission(_ author: User) -> ChatMessage {
        ChatMessage(author: author, kind: .submission, sentAt: .now)
    }

    // MARK: - Header: name and monogram

    @Test func circleNameIsTheCircleName() {
        #expect(vm().circleName == "Dean St.")
    }

    @Test func monogramIsTheFirstLetterOfTheName() {
        #expect(vm().monogram == "D")
    }

    /// A circle can't be created without a name, but an empty one must not crash
    /// the header — `prefix(1)` on "" is "", so the badge just renders blank.
    @Test func monogramOfAnEmptyNameIsEmptyNotACrash() {
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([me], createdBy: me.id, name: ""),
                               me: me)
        #expect(vm.monogram == "")
        #expect(vm.circleName == "")
    }

    @Test func monogramUsesTheWholeFirstCharacterForEmoji() {
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([me], createdBy: me.id, name: "🌮 Tuesdays"),
                               me: me)
        #expect(vm.monogram == "🌮")
    }

    // MARK: - Header: member line

    @Test func memberLineListsUpToThreeFirstNames() {
        #expect(vm().memberLine == "Dave, Arnell, Sawyer +1 more")
    }

    @Test func memberLineOfExactlyThreeHasNoOverflowSuffix() {
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([dave, arnell, sawyer], createdBy: dave.id),
                               me: me)
        #expect(vm.memberLine == "Dave, Arnell, Sawyer")
    }

    @Test func memberLineOfOneIsJustThatName() {
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([me], createdBy: me.id), me: me)
        #expect(vm.memberLine == "You")
    }

    /// Not reachable through the app (you're always a member of a circle you're
    /// looking at), but the string builder must not produce a stray "+N more".
    @Test func memberLineOfAnEmptyRosterIsEmpty() {
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([], createdBy: nil), me: me)
        #expect(vm.memberLine == "")
    }

    @Test func memberLineCountsEveryExtraMemberInTheSuffix() {
        let extras = (0..<7).map { Self.user("Extra \($0)") }
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([dave, arnell, sawyer] + extras,
                                                createdBy: dave.id),
                               me: me)
        #expect(vm.memberLine == "Dave, Arnell, Sawyer +7 more")
    }

    /// A single-word username has no surname to drop.
    @Test func memberLineUsesSingleWordUsernamesWhole() {
        let jmoney = Self.user("jmoney")
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([jmoney, me], createdBy: jmoney.id), me: me)
        #expect(vm.memberLine == "jmoney, You")
    }

    // MARK: - Header: cluster avatar

    @Test func clusterAvatarIsTheFirstMemberWhoIsNotMe() {
        let cluster = try! #require(vm().clusterAvatar)
        #expect(cluster.initials == "DS")       // Dave Slater
        #expect(cluster.avatarIndex == 0)       // first in the member list
    }

    /// In a circle of one there's nobody to tuck behind the badge, so the view
    /// draws the badge alone rather than a placeholder.
    @Test func clusterAvatarIsNilWhenIAmTheOnlyMember() {
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([me], createdBy: me.id), me: me)
        #expect(vm.clusterAvatar == nil)
    }

    /// Skips past me even when I'm listed first.
    @Test func clusterAvatarSkipsMeWhenIAmFirstInTheRoster() {
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([me, dave, arnell], createdBy: me.id), me: me)
        let cluster = try! #require(vm.clusterAvatar)
        #expect(cluster.initials == "DS")
        #expect(cluster.avatarIndex == 1)   // dave's position in [me, dave, arnell]
    }

    @Test func clusterAvatarInitialsFallBackToTwoLettersForOneWordNames() {
        let jmoney = Self.user("jmoney")
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([jmoney, me], createdBy: me.id), me: me)
        #expect(vm.clusterAvatar?.initials == "JM")
    }

    // MARK: - Edition strip: editor

    @Test func editorNameIsTheCreatorsFirstName() {
        #expect(vm().editorName == "Arnell")
    }

    /// A circle whose creator has left (or predates `created_by`) still needs an
    /// editor line, so it falls back to the first member.
    @Test func editorNameFallsBackToFirstMemberWhenCreatorIsNotAMember() {
        let ghost = UUID()
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([dave, arnell], createdBy: ghost), me: me)
        #expect(vm.editorName == "Dave")
    }

    @Test func editorNameFallsBackToFirstMemberWhenCreatorIsNil() {
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([dave, arnell], createdBy: nil), me: me)
        #expect(vm.editorName == "Dave")
    }

    /// Nobody to name ⇒ nil, and the view drops the whole editor row.
    @Test func editorNameIsNilWithNoMembersAtAll() {
        let vm = ChatViewModel(db: DatabaseService(),
                               summary: summary([], createdBy: nil), me: me)
        #expect(vm.editorName == nil)
    }

    // MARK: - Edition strip: countdown

    /// The VM just forwards to the domain clock; the arithmetic itself is
    /// covered in CircleChatTests. This pins that the view's tick reaches it.
    @Test func countdownForwardsTheTickToTheEditionClock() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(vm().countdown(at: now) == EditionCountdown.string(from: now))
    }

    // MARK: - Thread rows: shape

    @Test func rowsAreEmptyForAFreshCircle() {
        #expect(vm().rows.isEmpty)
    }

    @Test func rowsPreserveMessageOrderAndIds() {
        let messages = [text(dave, "first"), text(arnell, "second"), text(me, "third")]
        let rows = vm(messages).rows
        #expect(rows.map(\.text) == ["first", "second", "third"])
        #expect(rows.map(\.id) == messages.map(\.id))
    }

    @Test func myMessagesAreMarkedMineAndOthersAreNot() {
        let rows = vm([text(me, "mine"), text(dave, "theirs")]).rows
        #expect(rows[0].isMine)
        #expect(!rows[1].isMine)
    }

    @Test func rowsCarryFirstNameAndInitialsForTheAuthor() {
        let row = vm([text(dave, "hi")]).rows[0]
        #expect(row.authorName == "Dave")
        #expect(row.initials == "DS")
    }

    /// The palette index is the author's slot in the member list, so a member's
    /// colour is the same in every row they appear in.
    @Test func avatarIndexIsTheAuthorsPositionInTheRoster() {
        let rows = vm([text(dave, "a"), text(sawyer, "b"), text(me, "c")]).rows
        #expect(rows.map(\.avatarIndex) == [0, 2, 3])
    }

    /// A message from someone no longer in the roster (left the circle) has no
    /// slot; index 0 keeps it renderable instead of crashing on a nil index.
    @Test func avatarIndexIsZeroForAnAuthorWhoLeftTheCircle() {
        let stranger = Self.user("Gone Away")
        #expect(vm([text(stranger, "still here in the log")]).rows[0].avatarIndex == 0)
    }

    @Test func timeIsFormattedShortForEveryRow() {
        let sentAt = Date(timeIntervalSince1970: 1_780_000_000)
        let row = vm([text(dave, "hi", at: sentAt)]).rows[0]
        #expect(row.time == sentAt.formatted(date: .omitted, time: .shortened))
    }

    // MARK: - Thread rows: events

    /// The event's wording comes from the VM, not the view — the view only
    /// composes "<name> <text>".
    @Test func submissionEventsAreMarkedEventsAndCarryTheirWording() {
        let row = vm([submission(sawyer)]).rows[0]
        #expect(row.isEvent)
        #expect(row.text == "submitted a piece to this week's edition")
        #expect(row.authorName == "Sawyer")   // the view says "Sawyer submitted a piece…"
    }

    @Test func textMessagesAreNotEvents() {
        #expect(!vm([text(dave, "hi")]).rows[0].isEvent)
    }

    // MARK: - Thread rows: run grouping

    @Test func aLoneMessageStartsAndEndsItsRun() {
        let row = vm([text(dave, "solo")]).rows[0]
        #expect(row.isRunStart)
        #expect(row.isRunEnd)
    }

    @Test func consecutiveMessagesFromOneAuthorFormOneRun() {
        let rows = vm([text(dave, "1"), text(dave, "2"), text(dave, "3")]).rows
        #expect(rows.map(\.isRunStart) == [true, false, false])
        #expect(rows.map(\.isRunEnd) == [false, false, true])
    }

    @Test func aDifferentAuthorBreaksTheRun() {
        let rows = vm([text(dave, "1"), text(arnell, "2")]).rows
        #expect(rows.map(\.isRunStart) == [true, true])
        #expect(rows.map(\.isRunEnd) == [true, true])
    }

    /// A submission event between two of Dave's messages is chrome, not a turn —
    /// it must not split his bubbles into two runs.
    @Test func anEventBetweenMessagesDoesNotBreakTheRun() {
        let rows = vm([text(dave, "1"), submission(sawyer), text(dave, "2")]).rows
        #expect(rows[0].isRunStart)
        #expect(!rows[0].isRunEnd)     // dave's run continues past the event
        #expect(!rows[2].isRunStart)
        #expect(rows[2].isRunEnd)
    }

    /// Alternating authors means every row is both ends of its own run.
    @Test func alternatingAuthorsMakeEveryRowASingletonRun() {
        let rows = vm([text(dave, "a"), text(me, "b"), text(dave, "c"), text(me, "d")]).rows
        #expect(rows.allSatisfy { $0.isRunStart && $0.isRunEnd })
    }

    // MARK: - Send

    @Test func cannotSendAnUntouchedDraft() {
        #expect(!vm().canSend)
    }

    @Test func cannotSendWhitespaceOnly() {
        let vm = vm()
        vm.draft = "   \n\t "
        #expect(!vm.canSend)
    }

    @Test func canSendOnceThereIsRealText() {
        let vm = vm()
        vm.draft = "hi"
        #expect(vm.canSend)
    }

    @Test func sendAppendsMyMessageAndClearsTheDraft() {
        let vm = vm()
        vm.draft = "roof thing saturday?"
        vm.send()
        #expect(vm.rows.count == 1)
        #expect(vm.rows[0].text == "roof thing saturday?")
        #expect(vm.rows[0].isMine)
        #expect(vm.draft.isEmpty)
        #expect(!vm.canSend)   // the button greys out again
    }

    /// The bubble shows what was typed, minus the surrounding whitespace the
    /// trim already decided was not content.
    @Test func sendTrimsSurroundingWhitespace() {
        let vm = vm()
        vm.draft = "  hello  \n"
        vm.send()
        #expect(vm.rows[0].text == "hello")
    }

    @Test func sendingWhitespaceOnlyDoesNothing() {
        let vm = vm()
        vm.draft = "   "
        vm.send()
        #expect(vm.rows.isEmpty)
        #expect(vm.draft == "   ")   // nothing sent, so nothing cleared
    }

    @Test func sendingAnEmptyDraftDoesNothing() {
        let vm = vm()
        vm.send()
        #expect(vm.rows.isEmpty)
    }

    @Test func consecutiveSendsGroupIntoOneRun() {
        let vm = vm()
        vm.draft = "one"; vm.send()
        vm.draft = "two"; vm.send()
        #expect(vm.rows.map(\.text) == ["one", "two"])
        #expect(vm.rows.map(\.isRunStart) == [true, false])
        #expect(vm.rows.map(\.isRunEnd) == [false, true])
    }

    @Test func sendAppendsAfterSeededHistory() {
        let vm = vm([text(dave, "existing")])
        vm.draft = "reply"
        vm.send()
        #expect(vm.rows.map(\.text) == ["existing", "reply"])
    }

    /// Interior newlines are content — only the ends get trimmed.
    @Test func sendKeepsInteriorNewlines() {
        let vm = vm()
        vm.draft = "\nline one\nline two\n"
        vm.send()
        #expect(vm.rows[0].text == "line one\nline two")
    }

    // MARK: - Submissions in the thread

    /// A DB whose draft submissions are whatever the test says.
    private final class SubmissionSpy: DatabaseService, @unchecked Sendable {
        var stubbed: [Submission] = []
        var shouldThrow = false
        struct Boom: Error {}

        override func draftSubmissions(circleId: UUID) async throws -> [Submission] {
            if shouldThrow { throw Boom() }
            return stubbed
        }
    }

    private func spyVM(_ spy: SubmissionSpy, seed: [ChatMessage] = []) -> ChatViewModel {
        ChatViewModel(db: spy, summary: summary([dave, arnell, sawyer, me], createdBy: arnell.id),
                      me: me, seed: seed)
    }

    /// Fixture times, all in the recent past and in ascending order. Relative to
    /// now rather than pinned to a calendar date, because `send()` stamps `.now`
    /// — a fixed date would sort either side of it depending on when the suite
    /// runs.
    private func at(_ minute: Int) -> Date {
        Date.now.addingTimeInterval(TimeInterval(minute * 60) - 3600)
    }

    @Test func submissionsAppearAsEventRows() async {
        let spy = SubmissionSpy()
        spy.stubbed = [Submission(authorId: dave.id, at: at(0))]
        let vm = spyVM(spy)
        await vm.appear()
        #expect(vm.rows.count == 1)
        #expect(vm.rows[0].isEvent)
        #expect(vm.rows[0].authorName == "Dave")
        #expect(vm.rows[0].text == "submitted a piece to this week's edition")
    }

    /// Submissions interleave with chatter by time, rather than clumping at
    /// either end — the event reads as part of the conversation.
    @Test func submissionsInterleaveWithMessagesByTime() async {
        let spy = SubmissionSpy()
        spy.stubbed = [Submission(authorId: sawyer.id, at: at(5))]
        let vm = spyVM(spy, seed: [text(dave, "before", at: at(0)),
                                   text(arnell, "after", at: at(10))])
        await vm.appear()
        #expect(vm.rows.map(\.isEvent) == [false, true, false])
        #expect(vm.rows.map(\.text) == ["before",
                                        "submitted a piece to this week's edition",
                                        "after"])
    }

    /// Your own submission reads the same as anyone else's — the compose phase
    /// announces the act, never the content.
    @Test func myOwnSubmissionIsAnEventNotAMessage() async {
        let spy = SubmissionSpy()
        spy.stubbed = [Submission(authorId: me.id, at: at(0))]
        let vm = spyVM(spy)
        await vm.appear()
        #expect(vm.rows[0].isEvent)
        #expect(vm.rows[0].text == "submitted a piece to this week's edition")
    }

    /// Two submissions from one author are two rows — the thread reports acts,
    /// not a per-person flag.
    @Test func eachSubmissionIsItsOwnRow() async {
        let spy = SubmissionSpy()
        spy.stubbed = [Submission(authorId: dave.id, at: at(0)),
                       Submission(authorId: dave.id, at: at(3))]
        let vm = spyVM(spy)
        await vm.appear()
        #expect(vm.rows.count == 2)
        #expect(vm.rows.map(\.isEvent) == [true, true])
    }

    /// Someone who submitted and then left has no member row to render from, so
    /// their event drops rather than showing a nameless bubble.
    @Test func aSubmitterWhoIsNoLongerAMemberIsSkipped() async {
        let spy = SubmissionSpy()
        spy.stubbed = [Submission(authorId: UUID(), at: at(0)),
                       Submission(authorId: dave.id, at: at(1))]
        let vm = spyVM(spy)
        await vm.appear()
        #expect(vm.rows.count == 1)
        #expect(vm.rows[0].authorName == "Dave")
    }

    /// A refetch replaces the submissions rather than appending them — appear()
    /// runs again on every return to the screen.
    @Test func reloadingDoesNotDuplicateSubmissions() async {
        let spy = SubmissionSpy()
        spy.stubbed = [Submission(authorId: dave.id, at: at(0))]
        let vm = spyVM(spy)
        await vm.appear()
        await vm.appear()
        #expect(vm.rows.count == 1)
    }

    /// A failed fetch keeps the thread as-is — a flaky network shouldn't erase
    /// events that are already on screen.
    @Test func aFailedFetchLeavesTheThreadAlone() async {
        let spy = SubmissionSpy()
        spy.stubbed = [Submission(authorId: dave.id, at: at(0))]
        let vm = spyVM(spy, seed: [text(arnell, "hi", at: at(1))])
        await vm.appear()
        #expect(vm.rows.count == 2)

        spy.shouldThrow = true
        await vm.appear()
        #expect(vm.rows.count == 2)   // still both
    }

    /// Sending a message alongside submissions doesn't disturb them.
    @Test func sendingKeepsSubmissionsInThread() async {
        let spy = SubmissionSpy()
        spy.stubbed = [Submission(authorId: dave.id, at: at(0))]
        let vm = spyVM(spy)
        await vm.appear()
        vm.draft = "nice one"
        vm.send()
        #expect(vm.rows.count == 2)
        #expect(vm.rows.map(\.isEvent) == [true, false])
    }
}
