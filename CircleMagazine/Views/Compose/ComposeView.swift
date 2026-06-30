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

@Observable @MainActor
final class ComposeModel {
    enum Phase { case editing, posting, posted }

    struct Resolved {
        let videoURL: URL
        let id: String
        let title: String?
    }

    var linkText = ""
    var caption = ""
    private(set) var resolved: Resolved?
    private(set) var isResolving = false
    private(set) var phase: Phase = .editing
    private(set) var errorText: String?

    private let db: DatabaseService
    private let issueId: UUID?
    let author: User

    init(db: DatabaseService, issueId: UUID?, author: User) {
        self.db = db
        self.issueId = issueId
        self.author = author
    }

    var canPost: Bool { resolved != nil && issueId != nil && phase == .editing }

    /// Parse the pasted link and pull the YouTube title for the live preview.
    func resolve() async {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), case .youtube(let id)? = VideoSource(url) else {
            resolved = nil
            errorText = "That doesn't look like a YouTube link."
            return
        }
        errorText = nil
        isResolving = true
        let title = await YouTubeOEmbed.title(forVideoID: id)
        resolved = Resolved(videoURL: url, id: id, title: title)
        isResolving = false
    }

    func clearLink() {
        resolved = nil
        linkText = ""
        errorText = nil
    }

    func post() async {
        guard let resolved, let issueId else {
            errorText = "No live edition to post to yet — try again in a moment."
            return
        }
        phase = .posting
        errorText = nil
        do {
            try await db.createVideoPost(
                issueId: issueId, authorId: author.id,
                videoURL: resolved.videoURL,
                caption: caption.isEmpty ? nil : caption)
            phase = .posted
        } catch {
            errorText = "Couldn't post your video — \(error.localizedDescription)"
            phase = .editing
        }
    }
}

struct ComposeView: View {
    @State private var model: ComposeModel
    @Environment(\.dismiss) private var dismiss
    /// Called when the post lands, so the feed can refresh to include it.
    let onPosted: () async -> Void

    init(db: DatabaseService, issueId: UUID?, author: User, onPosted: @escaping () async -> Void) {
        _model = State(initialValue: ComposeModel(db: db, issueId: issueId, author: author))
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
            Button("Cancel") { dismiss() }
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
            Text("Paste a YouTube link to feature it in this Sunday's edition.")
                .font(Style.body).foregroundStyle(Style.meta).padding(.top, 7)

            typePills.padding(.vertical, 18)

            HStack(spacing: 11) {
                Image(systemName: "link").font(.system(size: 15)).foregroundStyle(Color(hex: 0xB4AFA8))
                TextField("Paste a YouTube link", text: $model.linkText)
                    .font(.system(size: 13.5))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit { Task { await model.resolve() } }
                Button("Paste") {
                    if let s = UIPasteboard.general.string {
                        model.linkText = s
                        Task { await model.resolve() }
                    }
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Style.ink)
                .padding(.horizontal, 13).padding(.vertical, 5)
                .overlay(Capsule().stroke(Style.ink, lineWidth: 1))
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Style.rule, lineWidth: 1))

            footnote.padding(.top, 11)
        }
        .padding(.horizontal, Style.Space.xl).padding(.top, 20)
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
                VideoCard(source: .youtube(id: resolved.id), author: model.author,
                          caption: model.caption.isEmpty ? nil : model.caption,
                          title: resolved.title)
                    .frame(height: 246)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 9, y: 3)
                    .allowsHitTesting(false)

                sectionLabel("Your note").padding(.top, 22).padding(.bottom, 12)
                HStack(alignment: .top, spacing: 11) {
                    avatar(model.author, size: 30)
                    TextField("Add a note…", text: $model.caption, axis: .vertical)
                        .font(.system(size: 14)).foregroundStyle(Color(hex: 0x2A2826))
                }

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

    private func linkedChip(_ resolved: ComposeModel.Resolved) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 18)).foregroundStyle(.red)
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
            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(resolved.id)/hqdefault.jpg")) {
                $0.resizable().scaledToFill()
            } placeholder: { Color.black }
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
