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
        let shape: CardShape
        // Instagram: the scraped cover frame + @handle, so the preview shows the
        // real card and post() can re-host without scraping again.
        var insta: InstagramEmbed.Meta? = nil
    }

    var linkText = ""
    var caption = ""
    var captionStyle: CaptionStyle = .paperPlate
    /// Author-chosen vertical crop for a reel poster (0 top…1 bottom), set by
    /// dragging the preview. Centered until they move it.
    var posterFocus: Double = 0.5
    private(set) var resolved: Resolved?
    private(set) var isResolving = false
    private(set) var phase: Phase = .editing
    private(set) var errorText: String?

    private let db: DatabaseService
    /// The live edition to post into. The feed provides it when loaded; when it
    /// couldn't (feed error), post() asks the DB directly rather than staying dead.
    private var issueId: UUID?
    /// The circle being posted into — used to ask the DB for the live edition
    /// when the caller didn't already hand us an issue id.
    private let circleId: UUID
    private(set) var resolveTask: Task<Void, Never>?   // exposed so tests can await it
    /// Stamps each resolve pass; a pass only touches state while its stamp is
    /// current, so cancelled/superseded passes can't strand the spinner.
    private var resolveGeneration = 0
    let author: User

    init(db: DatabaseService, issueId: UUID?, circleId: UUID, author: User) {
        self.db = db
        self.issueId = issueId
        self.circleId = circleId
        self.author = author
    }

    var canPost: Bool { resolved != nil && phase == .editing }

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

    /// Parse the pasted link and, for YouTube, pull the title for the live preview.
    private func resolve(generation: Int) async {
        guard generation == resolveGeneration else { return }   // cancelled before we began
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        log.info("resolve start: '\(trimmed, privacy: .public)'")
        guard let url = URL(string: trimmed), let source = VideoSource(url), !isRawFile(source) else {
            log.info("resolve exit: unparseable link")
            resolved = nil
            isResolving = false
            errorText = "Paste a YouTube or Instagram link."
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
        resolved = Resolved(videoURL: url, source: source, title: title,
                            shape: CardShape(mediaURL: url), insta: insta)
        isResolving = false
        log.info("resolve exit: resolved, title=\(title ?? "nil", privacy: .public)")
    }

    private func isRawFile(_ source: VideoSource) -> Bool {
        if case .rawFile = source { return true }
        return false
    }

    func clearLink() {
        resolved = nil
        linkText = ""
        errorText = nil
        posterFocus = 0.5
    }

    func post() async {
        guard let resolved, phase == .editing else { return }
        phase = .posting
        errorText = nil
        // No id from the feed means either the feed errored or the week hasn't
        // published yet; both resolve to "the edition this belongs in", which
        // opens a draft if this is the circle's first submission of the week.
        if issueId == nil {
            issueId = try? await db.issueIdForSubmission(circleId: circleId)
        }
        guard let issueId else {
            errorText = "Couldn't open this week's edition — try again in a moment."
            phase = .editing
            return
        }
        do {
            try await db.createVideoPost(
                issueId: issueId, authorId: author.id,
                videoURL: resolved.videoURL,
                caption: caption.isEmpty ? nil : caption,
                captionStyle: captionStyle, cardShape: resolved.shape,
                insta: resolved.insta, posterFocus: posterFocus)
            phase = .posted
        } catch {
            errorText = "Couldn't post your video — \(error.localizedDescription)"
            phase = .editing
        }
    }
}

#if DEBUG
extension ComposeModel {
    /// Jump straight to the compose step for canvas previews — no network.
    /// Lives here, not beside the preview: `resolved` and `phase` are
    /// `private(set)`, which only this file can reach.
    func previewResolved(url: String, title: String?) {
        guard let u = URL(string: url), let source = VideoSource(u) else { return }
        resolved = Resolved(videoURL: u, source: source, title: title,
                            shape: CardShape(mediaURL: u))
    }

    func previewMarkPosted() { phase = .posted }
}
#endif
