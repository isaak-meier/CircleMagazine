//
//  ComposeView.swift
//  CircleMagazine
//
//  The compose flow, presented as a sheet from the nav bar's + button. One sheet,
//  three states: paste a YouTube link → preview + add a note → confirmation.
//  Circle pulls the title/thumbnail via oEmbed; posting goes through
//  DatabaseService.createVideoPost, which persists the title to pages.title.
//

import SwiftUI
import UIKit   // UIPasteboard
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
    }

    var linkText = ""
    var caption = ""
    var captionStyle: CaptionStyle = .paperPlate
    private(set) var resolved: Resolved?
    private(set) var isResolving = false
    private(set) var phase: Phase = .editing
    private(set) var errorText: String?

    private let db: DatabaseService
    /// The live edition to post into. The feed provides it when loaded; when it
    /// couldn't (feed error), post() asks the DB directly rather than staying dead.
    private var issueId: UUID?
    private(set) var resolveTask: Task<Void, Never>?   // exposed so tests can await it
    /// Stamps each resolve pass; a pass only touches state while its stamp is
    /// current, so cancelled/superseded passes can't strand the spinner.
    private var resolveGeneration = 0
    let author: User

    init(db: DatabaseService, issueId: UUID?, author: User) {
        self.db = db
        self.issueId = issueId
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
        if case .youtube(let id) = source {   // Instagram has no keyless lookup, so no dead-link check either.
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
        }
        resolved = Resolved(videoURL: url, source: source, title: title,
                            shape: CardShape(mediaURL: url))
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
    }

    func post() async {
        guard let resolved, phase == .editing else { return }
        phase = .posting
        errorText = nil
        if issueId == nil {   // feed never loaded — ask the DB for the edition directly
            issueId = try? await db.currentIssueId()
        }
        guard let issueId else {
            errorText = "No live edition to post to yet — try again in a moment."
            phase = .editing
            return
        }
        do {
            try await db.createVideoPost(
                issueId: issueId, authorId: author.id,
                videoURL: resolved.videoURL,
                caption: caption.isEmpty ? nil : caption,
                captionStyle: captionStyle, cardShape: resolved.shape)
            phase = .posted
        } catch {
            errorText = "Couldn't post your video — \(error.localizedDescription)"
            phase = .editing
        }
    }
}

struct ComposeView: View {
    @State private var model: ComposeModel
    /// True when the clipboard holds something that looks like a link, learned
    /// via detectPatterns — metadata only, so it never triggers the paste prompt.
    @State private var clipboardHasURL = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Called when the post lands, so the feed can refresh to include it.
    let onPosted: () async -> Void

    init(db: DatabaseService, issueId: UUID?, author: User,
         onPosted: @escaping () async -> Void) {
        _model = State(initialValue: ComposeModel(db: db, issueId: issueId, author: author))
        self.onPosted = onPosted
    }

    /// Canvas previews inject a pre-staged model to land on a specific step.
    fileprivate init(model: ComposeModel, onPosted: @escaping () async -> Void) {
        _model = State(initialValue: model)
        self.onPosted = onPosted
    }

    // Mockup grays that aren't in the shared palette.
    private let faint   = Color(hex: 0x9A958E)
    private let hairline = Color(hex: 0xECE9E4)

    var body: some View {
        Group {
            if model.phase == .posted {
                confirmation
            } else {
                VStack(spacing: 0) {
                    grabber
                    header
                    ScrollView {
                        if model.resolved == nil { pasteStep } else { composeStep }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .background(Style.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var grabber: some View {
        Capsule().fill(Style.rule).frame(width: 36, height: 4).padding(.top, 10)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button("Cancel") { model.cancelResolving(); dismiss() }
                .font(.system(size: 14)).foregroundStyle(Style.meta)
            Spacer()
            Text("COMPOSE").font(Style.eyebrow).tracking(1.8).foregroundStyle(faint)
            Spacer()
            postButton
        }
        .padding(.horizontal, Style.Space.lg)
        .padding(.top, Style.Space.md).padding(.bottom, Style.Space.lg)
        .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
    }

    @ViewBuilder
    private var postButton: some View {
        switch model.phase {
        case .posting:
            ProgressView().controlSize(.small)
        default:
            if model.canPost {
                Button { Task { await model.post() } } label: {
                    Text("Post").font(.system(size: 13, weight: .semibold)).foregroundStyle(Style.paper)
                        .padding(.horizontal, 17).padding(.vertical, 7)
                        .background(Style.ink, in: Capsule())
                }
            } else {
                Text("Post").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0xC6C1B9))
            }
        }
    }

    // MARK: Step 1 — paste

    private var pasteStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Share a video").font(.system(size: 23, weight: .bold, design: .serif))
            Text("Paste a YouTube or Instagram link to feature it in this Sunday's edition.")
                .font(Style.body).foregroundStyle(Style.meta).padding(.top, 7)

            typePills.padding(.vertical, 18)

            // Plain field: iOS's own edit-menu Paste handles manual pasting with
            // no permission prompt. The suggestion chip below is the fast path.
            HStack(spacing: 11) {
                Image(systemName: "link").font(.system(size: 15)).foregroundStyle(Color(hex: 0xB4AFA8))
                TextField("Paste a YouTube or Instagram link", text: $model.linkText)
                    .font(.system(size: 13.5))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit { model.startResolving() }
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Style.rule, lineWidth: 1))

            // Field has text (typed or hand-pasted) → a Continue button to
            // proceed. Empty field but a link on the clipboard → the paste chip.
            if !model.linkText.trimmingCharacters(in: .whitespaces).isEmpty {
                continueButton.padding(.top, 11)
            } else if clipboardHasURL {
                pasteSuggestion.padding(.top, 11)
            }

            footnote.padding(.top, 11)
        }
        .padding(.horizontal, Style.Space.xl).padding(.top, 20)
        .task { await detectClipboardURL() }
        .onChange(of: scenePhase) { _, phase in
            // Re-check after the user copies a link in another app and returns.
            if phase == .active { Task { await detectClipboardURL() } }
        }
    }

    // Shown only when detectPatterns says the clipboard holds a link. Styled
    // like the app's other capsule buttons (see the "Link" type pill). The read
    // uses iOS's standard paste path — the system shows its own "Allow Paste?"
    // prompt; nil means the user declined, so we just no-op.
    private var pasteSuggestion: some View {
        Button {
            if let s = UIPasteboard.general.string {
                model.linkText = s
                model.startResolving()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 11, weight: .semibold))
                Text("Use copied link")
            }
            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Style.paper)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Style.ink, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // Advances a link that's already in the field (typed or hand-pasted) into
    // the preview — the manual-entry counterpart to the paste chip.
    private var continueButton: some View {
        Button { model.startResolving() } label: {
            HStack(spacing: 6) {
                Text("Continue")
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Style.paper)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Style.ink, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Metadata-only clipboard probe: does it hold a probable URL? Never reads
    /// the value, so no paste prompt.
    @MainActor
    private func detectClipboardURL() async {
        let found = (try? await UIPasteboard.general.detectedPatterns(for: [\.probableWebURL])) ?? []
        clipboardHasURL = found.contains(\.probableWebURL)
    }

    @ViewBuilder
    private var footnote: some View {
        if model.isResolving {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Fetching details…").font(.system(size: 11)).foregroundStyle(Style.meta)
            }
        } else if let err = model.errorText {
            Text(err).font(.system(size: 11)).foregroundStyle(.red)
        } else {
            // oEmbed gives title + thumbnail without a key; duration needs the Data API, so it's omitted.
            Text("Circle pulls in the title & thumbnail automatically.")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(faint)
        }
    }

    private var typePills: some View {
        // ponytail: only Link is wired; Photo/Write are inert placeholders matching the mockup's three-up.
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 11, weight: .semibold))
                Text("Link")
            }
            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Style.paper)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Style.ink, in: Capsule())

            ForEach(["Photo", "Write"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color(hex: 0xA8A39C))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .overlay(Capsule().stroke(Style.rule, lineWidth: 1))
            }
        }
    }

    // Four caption treatments (1a–1d). Tap re-renders the preview above.
    private var stylePicker: some View {
        HStack(spacing: 8) {
            ForEach(CaptionStyle.allCases) { style in
                let selected = model.captionStyle == style
                Button { model.captionStyle = style } label: {
                    Text(style.displayName)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Style.paper : Color(hex: 0xA8A39C))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background { if selected { Capsule().fill(Style.ink) } }
                        .overlay { if !selected { Capsule().stroke(Style.rule, lineWidth: 1) } }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Step 2 — preview + note

    @ViewBuilder
    private var composeStep: some View {
        if let resolved = model.resolved {
            VStack(alignment: .leading, spacing: 0) {
                if let err = model.errorText {
                    ErrorBanner(message: err).padding(.bottom, 14)
                }

                linkedChip(resolved)

                sectionLabel("How it appears in the edition").padding(.top, 18).padding(.bottom, 11)
                // The exact card the feed renders (CardView owns the paper,
                // corner radius, and shadow), so the preview can't drift.
                CardView(viewModel: CardViewModel(
                    previewing: resolved.source, author: model.author,
                    title: resolved.title,
                    caption: model.caption.isEmpty ? nil : model.caption,
                    captionStyle: model.captionStyle, cardShape: resolved.shape))
                    // Fixed height, NOT .feedCardFrame(): its containerRelativeFrame
                    // sizing feeds back against keyboard avoidance in this sheet's
                    // ScrollView and locks the main thread in a layout loop.
                    .frame(height: previewHeight(resolved.shape))
                    .allowsHitTesting(false)
                    // The comment field lives in the card's leftover paper area at
                    // the bottom — a white bordered pill, per the compose design.
                    .overlay(alignment: .bottom) { noteField }

                sectionLabel("Caption style").padding(.top, 22).padding(.bottom, 11)
                stylePicker

                Rectangle().fill(hairline).frame(height: 1).padding(.vertical, 18)

                HStack(spacing: 9) {
                    SwiftUI.Circle().fill(Style.edition).frame(width: 7, height: 7)
                    (Text("Appears in ").foregroundStyle(Style.meta)
                     + Text("This Sunday's Edition").foregroundStyle(Style.ink).bold())
                        .font(.system(size: 11.5))
                }
            }
            .padding(.horizontal, Style.Space.lg).padding(.top, 18)
        }
    }

    /// Card height per shape so media + plate + note fill it without a void:
    /// wide stacks a 16:9 region and the plate, square is taller, and tall is
    /// full-bleed media (the note overlays the media bottom there).
    private func previewHeight(_ shape: CardShape) -> CGFloat {
        switch shape {
        case .wide:   400
        case .square: 530
        case .tall:   440
        }
    }

    private var noteField: some View {
        HStack(spacing: 11) {
            avatar(model.author, size: 26)
            TextField("Add a comment…", text: $model.caption, axis: .vertical)
                .font(.system(size: 14)).foregroundStyle(Color(hex: 0x2A2826))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Style.rule, lineWidth: 1))
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    private func linkedChip(_ resolved: ComposeModel.Resolved) -> some View {
        HStack(spacing: 11) {
            if case .insta = resolved.source {
                Image(systemName: "camera.fill").font(.system(size: 16)).foregroundStyle(.pink)
            } else {
                Image(systemName: "play.rectangle.fill").font(.system(size: 18)).foregroundStyle(.red)
            }
            Text(resolved.title ?? resolved.videoURL.absoluteString)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Style.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                Text("Linked").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color(hex: 0x1F8A5B))
            Button { model.clearLink() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Style.meta)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Style.rule, lineWidth: 1))
    }

    // MARK: Step 3 — confirmation

    private var confirmation: some View {
        VStack(spacing: 0) {
            grabber
            VStack(spacing: 0) {
                SwiftUI.Circle().fill(Style.ink).frame(width: 58, height: 58)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 24, weight: .bold)).foregroundStyle(Style.paper))
                Text("You're in the edition")
                    .font(.system(size: 25, weight: .bold, design: .serif)).padding(.top, 22)
                Text("Your video joins the other pieces in this Sunday's issue. It goes live with the edition.")
                    .font(Style.body).foregroundStyle(Style.meta).multilineTextAlignment(.center)
                    .padding(.top, 10).frame(maxWidth: 280)

                if let resolved = model.resolved { scheduledRow(resolved).padding(.top, 26) }

                Button { Task { await onPosted(); dismiss() } } label: {
                    Text("View this week's edition")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Style.ink)
                        .overlay(alignment: .bottom) { Rectangle().fill(Style.ink).frame(height: 1.5).offset(y: 3) }
                }
                .padding(.top, 24)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 40).padding(.bottom, 40)
        }
    }

    private func scheduledRow(_ resolved: ComposeModel.Resolved) -> some View {
        HStack(spacing: 11) {
            scheduledThumbnail(resolved.source)
                .frame(width: 60, height: 40).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(Style.ink)
                    .padding(5).background(.white.opacity(0.92), in: SwiftUI.Circle()))
            VStack(alignment: .leading, spacing: 3) {
                Text(resolved.title ?? "Untitled")
                    .font(.system(size: 13, weight: .bold, design: .serif)).foregroundStyle(Style.ink)
                    .lineLimit(2)
                Text("Scheduled · \(model.author.username)")
                    .font(.system(size: 10)).foregroundStyle(faint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Style.rule, lineWidth: 1))
    }

    // YouTube has a keyless thumbnail URL; Instagram doesn't, so fall back to the
    // same gradient the card shows for insta.
    @ViewBuilder
    private func scheduledThumbnail(_ source: VideoSource) -> some View {
        switch source {
        case .youtube(let id):
            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")) {
                $0.resizable().scaledToFill()
            } placeholder: { Color.black }
        default:
            LinearGradient(colors: [.purple, .orange, .pink],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 8.5, weight: .semibold)).tracking(1.4).foregroundStyle(faint)
    }

    private func avatar(_ user: User, size: CGFloat) -> some View {
        SwiftUI.Circle().fill(Color(hex: 0xE3E0DB))
            .frame(width: size, height: size)
            .overlay(Text(user.username.prefix(1)).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6B6862)))
    }
}

#if DEBUG
extension ComposeModel {
    /// Jump straight to the compose step for canvas previews — no network.
    fileprivate func previewResolved(url: String, title: String?) {
        guard let u = URL(string: url), let source = VideoSource(u) else { return }
        resolved = Resolved(videoURL: u, source: source, title: title,
                            shape: CardShape(mediaURL: u))
    }

    fileprivate func previewMarkPosted() { phase = .posted }
}



#Preview("Compose step — note in card") {
    let model = ComposeModel(db: DatabaseService(), issueId: nil,
                             author: Magazine.sample.pages[0].author!)
    model.previewResolved(url: "https://www.youtube.com/watch?v=62bIsvRcPv0",
                          title: "I Spent 3 Weeks Living Off-Grid in the Mountains")
    return ComposeView(model: model) {}
}

#Preview("Confirmation") {
    let model = ComposeModel(db: DatabaseService(), issueId: nil,
                             author: Magazine.sample.pages[0].author!)
    model.previewResolved(url: "https://www.youtube.com/watch?v=62bIsvRcPv0",
                          title: "I Spent 3 Weeks Living Off-Grid in the Mountains")
    return ComposeView(model: model) {}
        .onAppear { model.previewMarkPosted() }
}
#endif
