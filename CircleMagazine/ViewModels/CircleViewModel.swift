//
//  CircleViewModel.swift
//  CircleMagazine
//
//  The circle (community) screen's ViewModel: identity, roster, invite, and the
//  "who's submitted" set. Holds its edition as a child `IssueViewModel`, so the
//  circle screen binds to `circle.*` for chrome and `circle.issue.*` for the
//  magazine body.
//

import Foundation

@Observable @MainActor
final class CircleViewModel {
  /// The circle's data aggregate. Exposed (it's domain data, not a service) so
  /// the invite sheet can read it.
  let summary: CircleSummary
  private let db: DatabaseService
  let me: User
  /// The two phases of a circle, one child VM each: the published edition and
  /// the chat the week is assembled in. `issue.state` picks which one shows.
  let issue: IssueViewModel
  let chat: ChatViewModel

  init(summary: CircleSummary, db: DatabaseService, me: User,
       issue: IssueViewModel, chat: ChatViewModel) {
    self.summary = summary
    self.db = db
    self.me = me
    self.issue = issue
    self.chat = chat
  }

  var circleId: UUID     { summary.circle.id }
  var name: String       { summary.name }
  var members: [User]    { summary.members }
  var inviteCode: String { summary.circle.inviteCode }
  var editorId: UUID?    { summary.circle.createdBy }
  var isEditor: Bool     { summary.circle.createdBy == me.id }

  /// Members who've submitted a page to this edition — the roster's "submitted"
  /// set. Empty until `loadSubmitters()` runs (or if it fails).
  private(set) var submitters: Set<UUID> = []

  func loadSubmitters() async {
    submitters = (try? await db.submitterIds(among: members.map(\.id), circleId: circleId)) ?? []
  }
}
