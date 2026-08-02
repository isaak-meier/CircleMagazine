//
//  ComposeModel.swift
//  CircleMagazine
//
//  The compose sheet's ViewModel: the pasted link's resolve state machine and
//  the post command. It holds DatabaseService and drives a screen, so it lives
//  with the other ViewModels rather than beside ComposeView — paste, resolve,
//  and post are all exercisable without a single SwiftUI type.
//

import Foundation
import os

private let log = Logger(subsystem: "CircleMagazine", category: "compose")

@Observable @MainActor
final class ComposeModel {
    enum Phase { case editing, posting, posted }

    struct Resolved {
        let videoURL: URL
        let source: VideoSource
        let title: String?
        // Instagram: the scraped cover frame + @handle, so the preview shows the
        // real card and post() can re-host without scraping again.
        var insta: InstagramEmbed.Meta? = nil
    }

    /// What the author has staged to post. One case at a time by construction —
    /// a link and a photo can't both be half-entered, and "nothing yet" is the
    /// nil, not a third case to forget about.
    enum Draft {
        case link(Resolved)
        case photo(Photo)
        case web(WebLink)
    }

    /// A pasted link with no player of its own. `meta` is what the scrape found,
    /// nil included — a page that publishes nothing is still postable, so the
    /// absence of metadata is a value here rather than a failure to handle.
    struct WebLink {
        let url: URL
        let meta: OpenGraph.Meta?
    }

    /// A picked photo, already encoded to the bytes that get uploaded.
    struct Photo {
        let jpeg: Data
        /// A local URL for the preview, so the card renders the real photo
        /// without a round trip through storage.
        let previewURL: URL
    }

    var linkText = ""
    var caption = ""
    /// Author-chosen vertical crop for a reel poster (0 top…1 bottom), set by
    /// dragging the preview. Centered until they move it.
    var posterFocus: Double = 0.5
    private(set) var draft: Draft?
    /// The staged link, when that's what's staged. Derived from `draft` rather
    /// than stored alongside it — there's still exactly one source of truth.
    var resolved: Resolved? {
        if case .link(let r) = draft { return r }
        return nil
    }
    /// The staged photo, likewise.
    var photo: Photo? {
        if case .photo(let p) = draft { return p }
        return nil
    }
    /// The staged plain link, likewise.
    var webLink: WebLink? {
        if case .web(let w) = draft { return w }
        return nil
    }
    private(set) var isResolving = false
    private(set) var phase: Phase = .editing
    private(set) var errorText: String?

    private let db: DatabaseService
    /// The circle being posted into. The edition is NOT passed in — `post()`
    /// asks the DB which one a submission belongs in, every time.
    ///
    /// The caller used to seed the loaded (live) issue id to save a round trip.
    /// That silently became "post into the edition everyone is currently
    /// reading" once liveness was derived, so the only safe answer is to not
    /// let a caller name the edition at all.
    private let circleId: UUID
    private(set) var resolveTask: Task<Void, Never>?   // exposed so tests can await it
    /// Stamps each resolve pass; a pass only touches state while its stamp is
    /// current, so cancelled/superseded passes can't strand the spinner.
    private var resolveGeneration = 0
    let author: User

    init(db: DatabaseService, circleId: UUID, author: User) {
        self.db = db
        self.circleId = circleId
        self.author = author
    }

    var canPost: Bool { draft != nil && phase == .editing }

    /// "August 1" — the edition this submission joins.
    var editionName: String { EditionCountdown.editionName() }
    /// "Sunday, August 2" — when it becomes readable. Named explicitly because
    /// posting mid-week and then finding nothing in the live edition is the
    /// single most confusing thing about the weekly cycle.
    var opensOn: String { EditionCountdown.opensOn() }

    /// Kick off `resolve`, replacing any fetch already in flight.
    func startResolving() {
        if resolveTask != nil { log.info("startResolving: superseding in-flight fetch") }
        resolveTask?.cancel()
        resolveGeneration += 1
        let generation = resolveGeneration
        resolveTask = Task { await resolve(generation: generation) }
    }

    /// Abort an in-flight fetch (Cancel button) so its result can't land later.
    func cancelResolving() {
        log.info("cancelResolving")
        resolveTask?.cancel()
        resolveTask = nil
        resolveGeneration += 1   // orphan any pass already running (or yet to run)
        isResolving = false
    }

    /// Parse the pasted link and fetch whatever the source can tell us about it —
    /// a YouTube title, an Instagram cover frame, or Open Graph tags for anything
    /// else. Every fetch here is best-effort: a miss previews with less, it
    /// doesn't block the post.
    private func resolve(generation: Int) async {
        guard generation == resolveGeneration else { return }   // cancelled before we began
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        log.info("resolve start: '\(trimmed, privacy: .public)'")
        guard let url = URL(string: trimmed), let source = VideoSource(url) else {
            log.info("resolve exit: unparseable link")
            draft = nil
            isResolving = false
            errorText = "That doesn't look like a link."
            return
        }
        // Anything that isn't a player we can embed is a plain web link, and
        // `.rawFile` is how VideoSource spells "some other URL".
        if isRawFile(source) {
            await resolveWebLink(url, generation: generation)
            return
        }
        errorText = nil
        isResolving = true
        var title: String?
        var insta: InstagramEmbed.Meta?
        switch source {
        case .youtube(let id):
            let began = Date()
            let lookup = await YouTubeOEmbed.lookup(forVideoID: id)
            log.info("resolve: oEmbed took \(Date().timeIntervalSince(began), format: .fixed(precision: 1))s → \(String(describing: lookup), privacy: .public)")
            guard generation == resolveGeneration else {
                log.info("resolve exit: cancelled/superseded mid-fetch")
                return   // canceller or successor owns the state now
            }
            switch lookup {
            case .found(let t): title = t
            case .unavailable:
                isResolving = false
                errorText = "That video looks private or removed — check the link."
                return
            case .unknown: break   // can't tell; post without a title rather than block
            }
        case .insta(let id, let kind):
            // Best-effort: scrape the cover frame + @handle for the preview. A
            // miss just posts with the gradient fallback, so don't block on it.
            insta = await InstagramEmbed.fetch(id: id, kind: kind)
            guard generation == resolveGeneration else {
                log.info("resolve exit: cancelled/superseded mid-fetch")
                return
            }
        case .rawFile: break
        }
        draft = .link(Resolved(videoURL: url, source: source, title: title, insta: insta))
        isResolving = false
        log.info("resolve exit: resolved, title=\(title ?? "nil", privacy: .public)")
    }

    /// A link with no player: scrape Open Graph tags for the preview and stage
    /// it either way.
    ///
    /// The scrape can't fail the paste. Most of the web publishes no usable
    /// metadata, and "this site didn't fill in its meta tags" is not a reason a
    /// member can't share it — the card falls back to naming it by its host.
    private func resolveWebLink(_ url: URL, generation: Int) async {
        // http is refused up front rather than after a round trip: the fetch
        // would be blocked by App Transport Security anyway, and the author
        // deserves the reason now.
        guard url.scheme == "https" else {
            log.info("resolve exit: non-https link")
            draft = nil
            isResolving = false
            errorText = "Links need to start with https."
            return
        }
        errorText = nil
        isResolving = true
        let meta = await OpenGraph.fetch(url)
        guard generation == resolveGeneration else {
            log.info("resolve exit: cancelled/superseded mid-scrape")
            return   // canceller or successor owns the state now
        }
        draft = .web(WebLink(url: url, meta: meta))
        isResolving = false
        log.info("resolve exit: web link, metadata=\(meta != nil, privacy: .public)")
    }

    /// Stage a photo the author picked. Replaces whatever was staged — picking a
    /// photo after pasting a link swaps the draft rather than stacking on it.
    func stagePhoto(jpeg: Data, previewURL: URL) {
        cancelResolving()          // a link still resolving would land on top of this
        linkText = ""
        errorText = nil
        draft = .photo(Photo(jpeg: jpeg, previewURL: previewURL))
    }

    private func isRawFile(_ source: VideoSource) -> Bool {
        if case .rawFile = source { return true }
        return false
    }

    /// Unstage whatever's staged, back to the pick step.
    func clearLink() {
        draft = nil
        linkText = ""
        errorText = nil
        posterFocus = 0.5
    }

    func post() async {
        guard let draft, phase == .editing else { return }
        phase = .posting
        errorText = nil
        // Asked fresh on every post: the answer is the circle's open draft,
        // opened here if this is the first submission of the week. Never cached
        // across posts — the edition rolls over at the week boundary, and a
        // sheet left open across it would otherwise write into last week.
        guard let issueId = try? await db.issueIdForSubmission(circleId: circleId) else {
            errorText = "Couldn't open this week's edition — try again in a moment."
            phase = .editing
            return
        }
        let note = caption.isEmpty ? nil : caption
        do {
            switch draft {
            case .link(let resolved):
                try await db.createVideoPost(
                    issueId: issueId, circleId: circleId, authorId: author.id,
                    videoURL: resolved.videoURL, caption: note,
                    insta: resolved.insta, posterFocus: posterFocus)
            case .photo(let photo):
                try await db.createPhotoPost(
                    issueId: issueId, circleId: circleId, authorId: author.id,
                    jpeg: photo.jpeg, caption: note)
            case .web(let link):
                // The metadata scraped at paste time, not a fresh fetch: the
                // author approved a specific preview and that's what ships.
                try await db.createLinkPost(
                    issueId: issueId, circleId: circleId, authorId: author.id,
                    url: link.url, meta: link.meta, caption: note)
            }
            phase = .posted
        } catch {
            errorText = "Couldn't post — \(error.localizedDescription)"
            phase = .editing
        }
    }
}

#if DEBUG
extension ComposeModel {
    /// Jump straight to the compose step for canvas previews — no network.
    /// Lives here, not beside the preview: `resolved` and `phase` are
    /// `private(set)`, which only this file can reach.
    func previewResolved(url: String, title: String?, insta: InstagramEmbed.Meta? = nil) {
        guard let u = URL(string: url), let source = VideoSource(u) else { return }
        draft = .link(Resolved(videoURL: u, source: source, title: title, insta: insta))
    }

    /// Stage a plain web link without scraping it — `meta` is what the scrape
    /// would have found, nil included.
    func previewWebLink(_ url: String, meta: OpenGraph.Meta?) {
        guard let u = URL(string: url) else { return }
        draft = .web(WebLink(url: u, meta: meta))
    }

    func previewMarkPosted() { phase = .posted }
}
#endif
