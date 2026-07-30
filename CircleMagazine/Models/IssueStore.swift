//
//  IssueStore.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/22/26.
//

import Foundation

enum IssueLoadState {
  case loading
  case loaded(Magazine)
  /// The compose phase: nothing is live for this circle, the next edition is
  /// being assembled. A phase, not a failure — the circle shows its chat.
  case composing
  case failedToLoad(error: String)
}

@Observable // view is re-rendered when any properties change
@MainActor // all code runs on main thread serialized
final class IssueStore {
  let db: DatabaseService
  /// Each circle's current edition, keyed by circle id. A circle we've never
  /// fetched is absent ⇒ reads as `.loading` via `state(for:)`.
  private var issueLoadStates: [UUID: IssueLoadState]

  init(db: DatabaseService, circleIds: [UUID] = []) {
    self.db = db
    issueLoadStates = Dictionary(uniqueKeysWithValues: circleIds.map { ($0, IssueLoadState.loading) })
  }

  /// The circle's edition — `.loading` for any circle not yet fetched.
  func state(for circle: UUID) -> IssueLoadState { issueLoadStates[circle] ?? .loading }

  /// First load for a circle — fetches once, then no-ops (idempotent).
  func load(circleId: UUID) async {
    if case .loaded = issueLoadStates[circleId] { return }  // already have it
    await refresh(circleId: circleId)
  }

  /// Force a full fetch and replace this circle's cache. No `.loading` flip, so
  /// an already-loaded magazine stays on screen until the new one arrives.
  func refresh(circleId: UUID) async {
    do {
      // nil = nothing live = the compose phase. Only a thrown error is a failure.
      let fetched = try await db.fetchCurrentIssue(circleId: circleId)
      // Signing out cancels the warm that's mid-flight, but its already-issued
      // fetches still return — writing them here would repopulate the cache
      // straight after `invalidateAll` cleared it, leaking the old account's
      // editions into the next session.
      if Task.isCancelled { return }
      if let magazine = fetched {
        issueLoadStates[circleId] = .loaded(magazine)
      } else {
        issueLoadStates[circleId] = .composing
      }
    } catch is CancellationError {
      // Whoever asked went away — that's not a failed edition. Clobbering the
      // state here put the whole circle on the error screen when a card's task
      // was cancelled mid-refresh.
      return
    } catch {
      issueLoadStates[circleId] = .failedToLoad(error: error.localizedDescription)
    }
  }

  /// Cheap staleness check: full-fetch if nothing's cached, refresh only when a
  /// new issue went live, otherwise spend nothing.
  func refreshIfNeeded(circleId: UUID) async {
    // Showing the draft: the staleness check below compares against the LIVE
    // issue id, which is a different edition entirely, so it would refetch every
    // time anyway. Skip straight to the refetch — and it's what you want while
    // testing, since the draft changes under you as you post into it.
    guard !DatabaseService.isShowingDraft else {
      await refresh(circleId: circleId)
      return
    }
    guard case .loaded(let cached) = issueLoadStates[circleId] else {
      await load(circleId: circleId)  // nothing cached yet → first load
      return
    }
    do {
      let liveId = try await db.currentIssueId(circleId: circleId)
      if liveId != cached.issue.id { await refresh(circleId: circleId) }  // new issue → refetch
    } catch {
      // transient check failure → keep showing the cached magazine
    }
  }

  /// Preload several circles' editions into the cache concurrently, so tapping
  /// into a circle is instant. Each `load` no-ops if already cached. Called on
  /// launch once the circle list is known.
  func warm(circleIds: [UUID]) async {
    await withTaskGroup(of: Void.self) { group in
      for id in circleIds {
        group.addTask { [weak self] in await self?.load(circleId: id) }
      }
    }
  }

  /// Drop every cached edition (e.g. after a global preference change), so the
  /// next `state(for:)`/`refreshIfNeeded` refetches fresh.
  func invalidateAll() { issueLoadStates.removeAll() }
}

#if DEBUG
extension IssueStore {
  /// A store frozen with one circle's state — no fetch, for previews/tests.
  static func preview(circleId: UUID, _ state: IssueLoadState) -> IssueStore {
    let store = IssueStore(db: DatabaseService())
    store.issueLoadStates[circleId] = state
    return store
  }
}
#endif
