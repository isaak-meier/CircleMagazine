//
//  CommentsModel.swift
//  CircleMagazine
//
//  The comments sheet's ViewModel: loads a page's comments oldest-first and
//  posts new ones. Holds DatabaseService privately, so CommentsView binds to
//  `state` / `draft` / `canSend` and never sees a service.
//

import Foundation

@Observable @MainActor
final class CommentsModel {
    enum LoadState { case loading, loaded([CommentWithAuthor]), failed(String) }

    private(set) var state: LoadState = .loading
    var draft = ""
    private(set) var posting = false

    private let db: DatabaseService
    private let pageId: UUID
    let me: User

    init(db: DatabaseService, pageId: UUID, me: User) {
        self.db = db
        self.pageId = pageId
        self.me = me
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !posting
    }

    func load() async {
        do { state = .loaded(try await db.fetchComments(pageId: pageId)) }
        catch { state = .failed(error.localizedDescription) }
    }

    func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !posting else { return }
        posting = true
        defer { posting = false }
        do {
            let comment = try await db.postComment(pageId: pageId, userId: me.id, body: body)
            let added = CommentWithAuthor(comment: comment, author: me)
            var list = if case .loaded(let existing) = state { existing } else { [CommentWithAuthor]() }
            list.append(added)
            state = .loaded(list)
            draft = ""
        } catch {
            // Keep the draft so the user can retry; surface via the empty/failed
            // path only when there's nothing else on screen.
            if case .loaded = state {} else { state = .failed(error.localizedDescription) }
        }
    }
}
