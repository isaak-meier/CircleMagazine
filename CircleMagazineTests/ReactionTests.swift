//
//  ReactionTests.swift
//  CircleMagazineTests
//
//  Photo reactions: the storage path they're written to, how a stored row becomes
//  a face on a card, and the sentence VoiceOver reads for a cluster that shows no
//  number. All pure — no network, no camera.
//

import Foundation
import Testing
@testable import CircleMagazine

struct ReactionTests {

    // MARK: Fixtures

    private static func user(_ name: String) -> User {
        User(id: UUID(), username: name, bio: nil, avatarUrl: nil, role: nil,
             followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    }

    private let dave = Self.user("Dave Slater")
    private let arnell = Self.user("Arnell Kray")
    private let sawyer = Self.user("Sawyer Finch")

    private func page() -> Page {
        Page(id: UUID(), issueId: UUID(), submittedBy: nil, title: nil, caption: nil,
             captionStyle: nil, cardShape: nil, createdAt: nil)
    }

    private func reaction(by user: User, path: String = "circle/reactions/x.jpg",
                          at minute: Int = 0) -> ReactionWithAuthor {
        ReactionWithAuthor(
            reaction: Reaction(id: UUID(), pageId: UUID(), userId: user.id,
                               mediaPath: path,
                               createdAt: Date(timeIntervalSince1970: TimeInterval(minute * 60))),
            author: user)
    }

    private func card(_ reactions: [ReactionWithAuthor], me: User? = nil) -> CardViewModel {
        CardViewModel(from: MagazinePage(page: page(), pageMedia: [], author: nil,
                                         reactions: reactions),
                      meId: me?.id)
    }

    // MARK: - The storage path
    //
    // This is where the feature is most easily got wrong: the storage policy
    // compares the first path segment against `circle_id::text`, which Postgres
    // renders lowercase, while Swift's uuidString is uppercase. That mismatch
    // already made the media policy deny everything once.

    @Test func theReactionPathIsAllLowercase() {
        let name = DatabaseService.reactionName(
            pageId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            userId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
        #expect(name == name.lowercased())
        #expect(name.contains("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
    }

    /// The circle folder has to stay the FIRST segment — the storage policy reads
    /// `foldername(name)[1]`, so nesting reactions any higher would deny the read.
    @Test func theReactionPathNestsUnderTheCircleFolderNotAboveIt() {
        let circle = UUID()
        let name = DatabaseService.reactionName(pageId: UUID(), userId: UUID())
        let full = "\(circle.uuidString.lowercased())/\(name)"
        let segments = full.split(separator: "/").map(String.init)
        #expect(segments[0] == circle.uuidString.lowercased())
        #expect(segments[1] == "reactions")
        #expect(segments.count == 3)
    }

    /// Deterministic, so reacting again overwrites rather than piling up files.
    @Test func theSamePersonAndPageAlwaysGetTheSamePath() {
        let page = UUID(), user = UUID()
        #expect(DatabaseService.reactionName(pageId: page, userId: user)
                == DatabaseService.reactionName(pageId: page, userId: user))
    }

    @Test func differentPeopleGetDifferentPathsOnTheSamePage() {
        let page = UUID()
        #expect(DatabaseService.reactionName(pageId: page, userId: UUID())
                != DatabaseService.reactionName(pageId: page, userId: UUID()))
    }

    // MARK: - Decoding

    /// The CodingKeys are hand-written, which is exactly where a typo hides.
    @Test func aReactionDecodesFromSnakeCase() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "page_id":"22222222-2222-2222-2222-222222222222",
         "user_id":"33333333-3333-3333-3333-333333333333",
         "media_path":"circle/reactions/a.jpg",
         "created_at":"2026-08-01T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reaction = try decoder.decode(Reaction.self, from: Data(json.utf8))
        #expect(reaction.mediaPath == "circle/reactions/a.jpg")
        #expect(reaction.userId.uuidString.lowercased().hasPrefix("33333333"))
    }

    // MARK: - Row → face

    @Test func aStoredReactionBecomesASignablePhotoAndAnAuthor() {
        let vm = card([reaction(by: dave, path: "circle/reactions/d.jpg")])
        #expect(vm.reactions.count == 1)
        #expect(vm.reactions[0].author?.username == "Dave Slater")
        // A path, never a URL — the bucket is private, the view signs it.
        #expect(vm.reactions[0].photo == .stored(path: "circle/reactions/d.jpg"))
    }

    @Test func reactionsKeepTheOrderTheyCameIn() {
        let vm = card([reaction(by: dave, at: 0),
                       reaction(by: arnell, at: 1),
                       reaction(by: sawyer, at: 2)])
        #expect(vm.reactions.compactMap { $0.author?.firstName } == ["Dave", "Arnell", "Sawyer"])
    }

    @Test func aPageWithNoReactionsHasNone() {
        #expect(card([]).reactions.isEmpty)
        #expect(card([]).myReaction == nil)
        #expect(card([]).reactionSummary == nil)
    }

    // MARK: - Whose reaction is it

    @Test func onlyTheViewersOwnReactionIsMine() {
        let vm = card([reaction(by: dave), reaction(by: arnell)], me: arnell)
        #expect(vm.reactions.map(\.isMine) == [false, true])
        #expect(vm.myReaction?.author?.username == "Arnell Kray")
    }

    /// No viewer (previews, the compose sheet) means nothing is mine — and in
    /// particular it must not default to the first reaction.
    @Test func withNoViewerNothingIsMine() {
        let vm = card([reaction(by: dave), reaction(by: arnell)])
        #expect(vm.reactions.allSatisfy { !$0.isMine })
        #expect(vm.myReaction == nil)
    }

    @Test func aViewerWhoHasNotReactedHasNoReactionOfTheirOwn() {
        let vm = card([reaction(by: dave)], me: arnell)
        #expect(vm.myReaction == nil)
        #expect(!vm.reactions.isEmpty)   // …but the others are still there
    }

    // MARK: - The spoken count
    //
    // The cluster shows faces and never a number, so this sentence is the only
    // place the count is stated at all — which makes it worth pinning.

    @Test func oneReactorIsNamed() {
        #expect(card([reaction(by: dave)]).reactionSummary == "Dave reacted")
    }

    @Test func twoReactorsAreBothNamed() {
        #expect(card([reaction(by: dave), reaction(by: arnell)]).reactionSummary
                == "Dave and Arnell reacted")
    }

    @Test func moreThanTwoNamesTheFirstTwoAndCountsTheRest() {
        let vm = card([reaction(by: dave), reaction(by: arnell), reaction(by: sawyer)])
        #expect(vm.reactionSummary == "Dave, Arnell and 1 others reacted")
    }

    /// Someone who left the circle has no user row, so there's no name to speak
    /// and no face to draw — they drop out rather than being read as a blank.
    @Test func aReactorWithNoUserRowIsNotNamed() {
        let ghost = ReactionWithAuthor(
            reaction: Reaction(id: UUID(), pageId: UUID(), userId: UUID(),
                               mediaPath: "circle/reactions/g.jpg", createdAt: nil),
            author: nil)
        let vm = card([reaction(by: dave), ghost])
        #expect(vm.reactionSummary == "Dave reacted")
        #expect(vm.reactions.count == 2)   // the photo is still there to open
    }

    // MARK: - Initials, now shared

    @Test func initialsTakeTwoWordsWhenThereAreTwo() {
        #expect(dave.initials == "DS")
    }

    @Test func initialsFallBackToTheFirstTwoCharactersOfOneWord() {
        #expect(Self.user("jmoney").initials == "JM")
    }

    @Test func initialsSurviveAOneCharacterName() {
        #expect(Self.user("j").initials == "J")
    }

    @Test func firstNameIsJustTheFirstWord() {
        #expect(dave.firstName == "Dave")
        #expect(Self.user("jmoney").firstName == "jmoney")
    }
}
