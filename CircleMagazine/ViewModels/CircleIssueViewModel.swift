//
//  CircleIssueViewModel.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 7/24/26.
//

import Foundation

/// The circle's edition. The only thing that reads the shared IssueStore cache;
/// the view binds to `state` and calls the commands, never seeing the store.
@Observable @MainActor
final class IssueViewModel {
  private let store: IssueStore
  let circleId: UUID
  let me: User

  init(store: IssueStore, circleId: UUID, me: User) {
    self.store = store
    self.circleId = circleId
    self.me = me
  }

  /// Debug override from Account → forces the compose phase whatever the DB
  /// says, so both circle screens can be exercised without flipping `is_live`.
  /// Re-read on `appear()`, so toggling it lands when you re-enter a circle.
  static let forceComposeKey = "debug.forceComposePhase"
  private var forcedCompose = UserDefaults.standard.bool(forKey: forceComposeKey)

  /// This circle's edition, straight from the shared cache.
  /// Both halves default to the harmless answer: an unset key reads `false`, so
  /// the override is off until someone flips it, and a circle the store hasn't
  /// heard of reads `.loading` — never `.composing`, never a failure. So a VM
  /// built before its first fetch shows the spinner, not the wrong phase.
  var state: IssueLoadState { forcedCompose ? .composing : store.state(for: circleId) }

  /// The live issue's id once loaded — nil while loading/failed. Compose needs it.
  var liveIssueId: UUID? {
    if case .loaded(let magazine) = state { return magazine.issue.id }
    return nil
  }

  func appear() async {
    forcedCompose = UserDefaults.standard.bool(forKey: Self.forceComposeKey)
    await store.refreshIfNeeded(circleId: circleId)
  }
  func refresh() async { await store.refresh(circleId: circleId) }

  /// Delete is a command — the view calls this, the VM talks to the Model.
  func delete(pageId: UUID) async {
    try? await store.db.deletePage(pageId: pageId)
    await refresh()
  }

  /// A comments VM for one of this edition's pages. Comments are their own
  /// concern (own VM), constructed here so the card stack never sees `db` or the
  /// factory — it only ever holds this IssueViewModel.
  func commentsVM(for pageId: UUID) -> CommentsModel {
    CommentsModel(db: store.db, pageId: pageId, me: me)
  }

  /// A fresh signed URL for a re-hosted reel poster. Command, not exposure —
  /// the card asks the VM, the VM asks the Model.
  func posterURL(path: String) async -> URL? {
    await store.db.posterSignedURL(path: path)
  }

  /// A compose VM for posting into this circle's live edition. Seeds it with the
  /// loaded issue id when we have it; otherwise compose asks the DB via circleId.
  func composeVM() -> ComposeModel {
    ComposeModel(db: store.db, issueId: liveIssueId, circleId: circleId, author: me)
  }
}

#if DEBUG
extension IssueViewModel {
  /// A VM whose store is frozen in a given state — no fetch, for previews.
  static func preview(_ state: IssueLoadState) -> IssueViewModel {
    let circleId = UUID()
    return IssueViewModel(
      store: .preview(circleId: circleId, state), circleId: circleId,
      me: User(id: UUID(), username: "You", bio: nil, avatarUrl: nil, role: nil,
               followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil))
  }
}
#endif
