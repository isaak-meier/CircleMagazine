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

  /// The loaded edition's id — nil while loading, failed, or composing. This is
  /// what's being *read*; it is not where submissions go (see `composeVM`).
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

  /// The page whose reaction is uploading, so its card can show it's working.
  private(set) var reactingPageId: UUID?

  /// React to a page with a photo, replacing your previous one if you had it.
  /// The card hands over a page id and bytes — the circle and the viewer are
  /// this VM's business, so a card can't react as somebody else.
  ///
  /// ponytail: a full edition refetch per reaction, same as `delete`. Keeps one
  /// source of truth; swap in an optimistic overlay if it ever feels slow.
  func react(pageId: UUID, jpeg: Data) async {
    reactingPageId = pageId
    defer { reactingPageId = nil }
    _ = try? await store.db.upsertReaction(pageId: pageId, circleId: circleId,
                                           userId: me.id, jpeg: jpeg)
    await refresh()
  }

  /// Take your reaction back.
  func unreact(pageId: UUID) async {
    try? await store.db.deleteReaction(pageId: pageId, userId: me.id)
    await refresh()
  }

  /// A comments VM for one of this edition's pages. Comments are their own
  /// concern (own VM), constructed here so the card stack never sees `db` or the
  /// factory — it only ever holds this IssueViewModel.
  func commentsVM(for pageId: UUID) -> CommentsModel {
    CommentsModel(db: store.db, pageId: pageId, me: me)
  }

  /// A fresh signed URL for a stored image — a member's photo or a re-hosted
  /// reel cover. Command, not exposure: the card asks the VM, the VM asks the
  /// Model.
  func signedURL(path: String) async -> URL? {
    await store.db.signedURL(path: path)
  }

  /// A compose VM for submitting into this circle. Only the circle is handed
  /// over — which edition a submission joins is the DB's call, and it's always
  /// the open draft, never the edition this VM currently has loaded.
  func composeVM() -> ComposeModel {
    ComposeModel(db: store.db, circleId: circleId, author: me)
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
