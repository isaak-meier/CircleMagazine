//
//  IssueLoader.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/22/26.
//

import Foundation

enum IssueLoadState {
  case loading
  case loaded(Magazine)
  case failedToLoad(error: String)
}

@Observable // view is re-rendered when any properties change
@MainActor // all code runs on main thread serialized
final class IssueLoader {
  let db: DatabaseService
  private(set) var loadState: IssueLoadState = .loading

  /// Account-screen preference: preview the newest draft issue instead of the
  /// live one. Read at fetch time, so a toggle just needs a refresh() after.
  static let showDraftKey = "showDraftIssue"
  private var live: Bool { !UserDefaults.standard.bool(forKey: Self.showDraftKey) }

  init(db: DatabaseService) {
    self.db = db
  }

  /// First load — fetches once, then no-ops (idempotent).
  func load() async {
    guard case .loading = loadState else { print("not refreshing"); return }
    await refresh()
  }

  /// Force a full fetch and replace the cache. No `.loading` flip, so an
  /// already-loaded magazine stays on screen until the new one arrives.
  func refresh() async {
    do {
      loadState = .loaded(try await db.fetchCurrentIssue(live: live))
    } catch {
      loadState = .failedToLoad(error: error.localizedDescription)
    }
  }

  /// Cheap staleness check for app load: full-fetch if nothing's cached,
  /// refresh only when a new issue went live, otherwise spend nothing.
  func refreshIfNeeded() async {
    guard case .loaded(let cachedState) = loadState else {
      await load()  // nothing cached yet → first load
      return
    }
    do {
      let liveId = try await db.currentIssueId(live: live)
      if liveId != cachedState.issue.id { await refresh() }  // new issue → refetch
    } catch {
      // transient check failure → keep showing the cached magazine
    }
  }
}

#if DEBUG
extension IssueLoader {
  /// A loader frozen in a given state — no fetch, for previews/tests.
  static func preview(_ state: IssueLoadState) -> IssueLoader {
    let loader = IssueLoader(db: DatabaseService())
    loader.loadState = state
    return loader
  }
}

#endif
