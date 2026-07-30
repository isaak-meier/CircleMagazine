//
//  ViewModelFactory.swift
//  CircleMagazine
//
//  The composition root for the view layer. Owns the shared services (the
//  IssueStore cache + DatabaseService) and assembles ViewModels from them, so
//  Views never see a service directly — they receive a ready-made ViewModel.
//  Built once in CircleMagazineApp and handed down; navigation calls the
//  `make…` methods to construct a screen's ViewModel on demand.
//

import Foundation

@MainActor
final class ViewModelFactory {
    private let db: DatabaseService
    /// The single, app-wide per-circle edition cache. An implementation detail
    /// of VM construction — nothing outside this factory holds it.
    private let store: IssueStore

    init(db: DatabaseService) {
        self.db = db
        self.store = IssueStore(db: db)
    }

    /// The Circles (bubble field) screen's VM. The list is fetched lazily by the
    /// VM itself on appear.
    func makeCirclesVM(me: User) -> CirclesViewModel {
        CirclesViewModel(db: db, store: store, me: me)
    }

    /// Drop every cached edition. The factory (and its store) live as long as the
    /// app, but ViewModels don't — so without this the next sign-in would find
    /// the previous account's circles already cached and `warm` would no-op on
    /// all of them. Called when the session ends.
    func reset() { store.invalidateAll() }

    /// A circle screen's VM graph: the community VM with its edition VM as a
    /// child, both wired to the shared services. The `summary` is already loaded
    /// by the caller (tapped bubble / join result), so this is pure assembly —
    /// no fetch, no async.
    func makeCircleVM(_ summary: CircleSummary, me: User) -> CircleViewModel {
        let issue = IssueViewModel(store: store, circleId: summary.circle.id, me: me)
        let chat = ChatViewModel(db: db, summary: summary, me: me)
        return CircleViewModel(summary: summary, db: db, me: me, issue: issue, chat: chat)
    }
}
