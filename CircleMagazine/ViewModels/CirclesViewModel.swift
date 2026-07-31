//
//  CirclesViewModel.swift
//  CircleMagazine
//
//  The Circles (bubble field) screen's ViewModel: owns the member's circle list
//  and the load / create / join commands, so the view never touches the DB.
//

import Foundation

@Observable @MainActor
final class CirclesViewModel {
    private let db: DatabaseService
    private let store: IssueStore
    let me: User

    enum LoadState {
      case loading,
           loaded([CircleSummary]),
           failed(String)
    }

    private(set) var state: LoadState = .loading

    init(db: DatabaseService, store: IssueStore, me: User) {
        self.db = db
        self.store = store
        self.me = me
    }

    /// First load — no-ops if the state was pre-seeded (previews) or already loaded.
    /// After the list lands, preloads every circle's edition into the store so
    /// tapping in is instant.
    func load() async {
        guard case .loading = state else { return }
        do {
            let circles = try await db.fetchCircles(memberOf: me.id)
            state = .loaded(circles)
            await store.warm(circleIds: circles.map(\.id))
            await scheduleEditionNudges()
        } catch {
            state = .failed("Couldn't load your circles — \(error.localizedDescription)")
        }
    }

    /// Creates the circle and grows a new bubble for it in place. Throws so the
    /// sheet can show the failure and keep the typed name for a retry.
    func create(named name: String) async throws {
        let circle = try await db.createCircle(name: name, creatorID: me.id)
        if case .loaded(let circles) = state {
            state = .loaded(circles + [CircleSummary(circle: circle, members: [me])])
        }
        await scheduleEditionNudges()
    }

    /// Joins via invite code and grows the circle's bubble in place. Throws so
    /// the sheet can show the failure (bad code, network) and keep the input.
    func join(code: String) async throws {
        let summary = try await db.joinCircle(code: code, userId: me.id)
        if case .loaded(let circles) = state, !circles.contains(where: { $0.id == summary.id }) {
            state = .loaded(circles + [summary])
        }
        await scheduleEditionNudges()
    }

    /// Line up "this week's edition is out" for every circle, on this device.
    ///
    /// Here because this is what owns the circle list, and it runs after create
    /// and join as well as load — so the permission prompt lands on someone who
    /// has just made or joined a circle and knows what they'd be notified about,
    /// rather than at launch before the app has shown them anything.
    private func scheduleEditionNudges() async {
        guard case .loaded(let circles) = state else { return }
        await EditionNotifications.reschedule(for: circles.map { (id: $0.id, name: $0.name) })
    }
}

#if DEBUG
extension CirclesViewModel {
    /// A VM frozen in a given state — no fetch, for previews.
    static func preview(_ state: LoadState) -> CirclesViewModel {
        let db = DatabaseService()
        let vm = CirclesViewModel(
            db: db, store: IssueStore(db: db),
            me: User(id: UUID(), username: "You", bio: nil, avatarUrl: nil, role: nil,
                     followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil))
        vm.state = state
        return vm
    }
}
#endif
