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
import PhotosUI   // PhotosPicker — no library permission prompt, the system owns the picker
import UIKit   // UIPasteboard

struct ComposeView: View {
    @State private var model: ComposeModel
    /// True when the clipboard holds something that looks like a link, learned
    /// via detectPatterns — metadata only, so it never triggers the paste prompt.
    @State private var clipboardHasURL = false
    /// The picker's selection. Watched rather than read, so loading the bytes
    /// stays off the main thread until the author actually picks something.
    @State private var pickedItem: PhotosPickerItem?
    @State private var loadingPhoto = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Called when the post lands, so the feed can refresh to include it.
    let onPosted: () async -> Void

    /// The compose VM is built by the edition's IssueViewModel (`composeVM()`),
    /// so this view never sees a DatabaseService. Previews inject a pre-staged
    /// model to land on a specific step.
    init(model: ComposeModel, onPosted: @escaping () async -> Void) {
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
                        if model.draft == nil { pasteStep } else { composeStep }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .background(Style.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        // Decoding happens here rather than in the model: PhotosPickerItem is a
        // SwiftUI type, so keeping it out of ComposeModel is what lets the model
        // be tested without the photo library.
        .task(id: pickedItem) { await loadPickedPhoto() }
    }

    /// Pull the picked photo's bytes and stage them. A HEIC from the library is
    /// re-encoded to JPEG, since that's what the bucket serves and what every
    /// client can decode.
    private func loadPickedPhoto() async {
        guard let pickedItem else { return }
        loadingPhoto = true
        defer { loadingPhoto = false }
        guard let raw = try? await pickedItem.loadTransferable(type: Data.self),
              let image = UIImage(data: raw),
              let jpeg = image.jpegData(compressionQuality: 0.85),
              let url = writePreview(jpeg) else { return }
        model.stagePhoto(jpeg: jpeg, previewURL: url)
    }

    /// AsyncImage wants a URL, so the preview bytes go to a temp file. Named for
    /// the sheet, overwritten each pick — the OS reclaims tmp, and a stale one
    /// is at most a single file.
    private func writePreview(_ jpeg: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-preview.jpg")
        do {
            try jpeg.write(to: url, options: .atomic)
            // Same path every time, so AsyncImage would serve the previous
            // photo from cache. A unique query defeats that without a new file.
            return URL(string: "\(url.absoluteString)?v=\(UUID().uuidString)")
        } catch {
            return nil
        }
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
            Text("Add to the edition").font(.system(size: 23, weight: .bold, design: .serif))
            Text("Pick a photo, or paste any link, for the \(model.editionName) edition.")
                .font(Style.body).foregroundStyle(Style.meta).padding(.top, 7)

            typePills.padding(.vertical, 18)

            // Plain field: iOS's own edit-menu Paste handles manual pasting with
            // no permission prompt. The suggestion chip below is the fast path.
            HStack(spacing: 11) {
                Image(systemName: "link").font(.system(size: 15)).foregroundStyle(Color(hex: 0xB4AFA8))
                TextField("Paste a link", text: $model.linkText)
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
        // ponytail: Write is still an inert placeholder from the mockup's three-up.
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 11, weight: .semibold))
                Text("Link")
            }
            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Style.paper)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Style.ink, in: Capsule())

            // The system picker: it runs out of process, so picking one photo
            // needs no library permission and no prompt.
            PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 6) {
                    if loadingPhoto {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "photo").font(.system(size: 11, weight: .semibold))
                    }
                    Text("Photo")
                }
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Style.ink)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .overlay(Capsule().stroke(Style.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text("Write")
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color(hex: 0xA8A39C))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .overlay(Capsule().stroke(Style.rule, lineWidth: 1))
        }
    }

    // A caption-style picker (paper plate / immersive / ink band / newsprint)
    // was drafted here and never wired up. Newsprint is the house style now and
    // the other three are gone, so there's nothing left to pick.

    // MARK: Step 2 — preview + note

    @ViewBuilder
    private var composeStep: some View {
        switch model.draft {
        case .link(let resolved): linkComposeStep(resolved)
        case .photo(let photo):   photoComposeStep(photo)
        case .web(let link):      webComposeStep(link)
        case nil:                 EmptyView()
        }
    }

    /// A plain link: the same chip → preview → note → spine as the others. It
    /// sizes to its own card, so no fixed height — a link with no cover image is
    /// a couple of lines tall and shouldn't be padded out to look broken.
    private func webComposeStep(_ link: ComposeModel.WebLink) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = model.errorText {
                ErrorBanner(message: err).padding(.bottom, 14)
            }

            webChip(link)

            sectionLabel("How it appears in the edition").padding(.top, 18).padding(.bottom, 11)
            CardView(viewModel: CardViewModel(
                previewingLink: link.url, meta: link.meta, author: model.author,
                caption: model.caption.isEmpty ? nil : model.caption))
                .allowsHitTesting(false)

            Spacer()
            noteField
            editionSpine
        }
        .padding(.horizontal, Style.Space.lg).padding(.top, 18)
    }

    /// Says which link is staged and, quietly, whether the site gave us anything
    /// to show — so "no picture" reads as the site's doing, not a bug.
    private func webChip(_ link: ComposeModel.WebLink) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "link").font(.system(size: 15)).foregroundStyle(Style.edition)
            Text(link.url.host() ?? link.url.absoluteString)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Style.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if link.meta == nil {
                Text("No preview").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Style.meta)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    Text("Linked").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0x1F8A5B))
            }
            Button { model.clearLink() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Style.meta)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Style.rule, lineWidth: 1))
    }

    /// A staged photo: the same chip → preview → note → "appears in" spine as a
    /// link, with the shape picker standing in for the link's crop drag.
    private func photoComposeStep(_ photo: ComposeModel.Photo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = model.errorText {
                ErrorBanner(message: err).padding(.bottom, 14)
            }

            photoChip

            sectionLabel("How it appears in the edition").padding(.top, 18).padding(.bottom, 11)
            CardView(viewModel: CardViewModel(
                previewingPhoto: photo.previewURL, author: model.author,
                caption: model.caption.isEmpty ? nil : model.caption))
                .allowsHitTesting(false)

            Spacer()
            noteField
            editionSpine
        }
        .padding(.horizontal, Style.Space.lg).padding(.top, 18)
    }

    private var photoChip: some View {
        HStack(spacing: 11) {
            Image(systemName: "photo.fill").font(.system(size: 16)).foregroundStyle(Style.edition)
            Text("Photo from your library")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Style.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                Text("Added").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color(hex: 0x1F8A5B))
            Button {
                pickedItem = nil
                model.clearLink()
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Style.meta)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Style.rule, lineWidth: 1))
    }

    // There was a wide / tall / square picker here. A photo card renders
    // full-bleed whatever the shape says (CardView's standardCard never reads
    // it — only Instagram does), so the control changed nothing on screen. The
    // column is still written, seeded from the photo's own orientation; bring
    // the picker back the day photo cards actually lay out by shape.

    private var editionSpine: some View {
        HStack(spacing: 9) {
            SwiftUI.Circle().fill(Style.edition).frame(width: 7, height: 7)
            (Text("Appears in the ").foregroundStyle(Style.meta)
             + Text("\(model.editionName) edition").foregroundStyle(Style.ink).bold()
             + Text(" · live \(model.opensOn)").foregroundStyle(Style.meta))
                .font(.system(size: 11.5))
        }
    }

    private func linkComposeStep(_ resolved: ComposeModel.Resolved) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                if let err = model.errorText {
                    ErrorBanner(message: err).padding(.bottom, 14)
                }

                linkedChip(resolved)

                sectionLabel("How it appears in the edition").padding(.top, 18).padding(.bottom, 11)
                // The exact card the feed renders (CardView owns the paper,
                // corner radius, and shadow), so the preview can't drift.
                // A reel's poster is draggable to reposition its crop; every
                // other preview stays inert.
                let reel = isReel(resolved)
                let vm = CardViewModel(
                    previewing: resolved.source, author: model.author,
                    title: resolved.title,
                    caption: model.caption.isEmpty ? nil : model.caption,
                    instaPoster: resolved.insta.map { .direct($0.posterURL) },
                    handle: resolved.insta?.handle, focus: model.posterFocus)
                let preview = CardView(viewModel: vm,
                    onPosterFocusChange: reel ? { model.posterFocus = $0 } : nil)

                if vm.hugsItsMedia {
                    // Sizes to its own media + plate, exactly like the feed, so
                    // the card is a true replica with no slack under the plate.
                    // Width-driven (aspectRatio), so it doesn't hit the
                    // containerRelativeFrame keyboard-loop that feedCardFrame did.
                    // Only a reel is touchable — dragging repositions its crop.
                    preview.allowsHitTesting(reel)
                } else {
                    // A square insta post fills its card rather than sizing to
                    // it, so it needs a height. NOT .feedCardFrame(): that
                    // containerRelativeFrame feeds back against keyboard
                    // avoidance in this sheet's ScrollView and locks the main
                    // thread in a layout loop.
                }

                Spacer()

                noteField

                editionSpine
            }
            .padding(.horizontal, Style.Space.lg).padding(.top, 18)
    }

    /// An Instagram reel — the only preview whose poster we let the author
    /// reposition (posts are square, YouTube isn't croppable here).
    private func isReel(_ resolved: ComposeModel.Resolved) -> Bool {
        if case .insta(_, let kind) = resolved.source { return kind != .post }
        return false
    }

    // The "Add a comment…" pill. Used inset inside a card (noteField, the
    // overlay path) and full-width below the reel card.
    private var noteFieldPill: some View {
        HStack(spacing: 11) {
            avatar(model.author, size: 26)
            TextField("Add a caption…", text: $model.caption, axis: .vertical)
                .font(.system(size: 14)).foregroundStyle(Color(hex: 0x2A2826))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Style.rule, lineWidth: 1))
    }

    private var noteField: some View {
        noteFieldPill.padding(.bottom, 16)
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

    /// A full-height page rather than a sheet that shrinks to its text: the
    /// sheet keeps the one `.large` detent it was presented at, so posting
    /// swaps the content without the sheet resizing under the author's hand.
    /// Ruled eyebrow up top, the mark centered, the action on the baseline —
    /// the same masthead/pill vocabulary as the rest of the app.
    private var confirmation: some View {
        VStack(spacing: 0) {
            grabber
            ruledEyebrow("SUBMITTED").padding(.top, 22)

            Spacer(minLength: Style.Space.xl)

            SwiftUI.Circle().fill(Style.ink).frame(width: 58, height: 58)
                .overlay(Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(Style.paper))
            Text("You're in the edition")
                .font(.system(size: 25, weight: .bold, design: .serif))
                .foregroundStyle(Style.ink)
                .padding(.top, Style.Space.xl)
            // Names the day, not "this Sunday" — an author who posts on
            // Tuesday and checks Wednesday needs to know nothing is wrong.
            (Text("Your post joins the ").foregroundStyle(Style.meta)
             + Text("\(model.editionName) edition").foregroundStyle(Style.ink).bold()
             + Text(". You'll see it \(model.opensOn), when the issue opens.")
                .foregroundStyle(Style.meta))
                .font(Style.body).multilineTextAlignment(.center)
                .padding(.top, Style.Space.md).frame(maxWidth: 280)

            // Only links get the thumbnail recap; a photo's confirmation
            // stands on its own rather than re-showing what was just picked.
            if let resolved = model.resolved {
                scheduledRow(resolved).padding(.top, Style.Space.xxl).frame(maxWidth: 320)
            }

            Spacer(minLength: Style.Space.xl)

            // Dismisses to the circle — which during compose is the chat, not
            // an edition. Saying "view the edition" would promise the very
            // thing the sentence above defers.
            CirclePillButton(title: "Back to the circle", filled: true, height: 50) {
                Task { await onPosted(); dismiss() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Style.Space.xxl)
        .padding(.bottom, 40)
    }

    /// Small-caps label with a hairline running out to both margins — the
    /// masthead's rule, at section scale.
    private func ruledEyebrow(_ text: String) -> some View {
        HStack(spacing: Style.Space.md) {
            Rectangle().fill(Style.rule).frame(height: 1)
            Text(text).font(Style.eyebrow).tracking(1.8).foregroundStyle(faint)
            Rectangle().fill(Style.rule).frame(height: 1)
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
                Text(scheduledName(resolved))
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

    /// What to call the thing just scheduled. YouTube gives us a title; a reel
    /// never has one, so it's named by its author the way Instagram names it —
    /// "Untitled" reads as something went wrong, and nothing did.
    private func scheduledName(_ resolved: ComposeModel.Resolved) -> String {
        if let title = resolved.title, !title.isEmpty { return title }
        if let handle = resolved.insta?.handle, !handle.isEmpty { return "@\(handle)" }
        switch resolved.source {
        case .youtube: return "YouTube video"
        case .insta:   return "Instagram post"
        case .rawFile: return "Video"
        }
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

// DEBUG-gated: the previews seed themselves via ComposeModel's debug-only hooks.
#if DEBUG
#Preview("Compose step — note in card") {
    let model = ComposeModel(db: DatabaseService(), circleId: UUID(),
                             author: Magazine.sample.pages[0].author!)
    model.previewResolved(url: "https://www.instagram.com/reels/DZXrc1uuezb/",
                          title: "I Spent 3 Weeks Living Off-Grid in the Mountains")
    return ComposeView(model: model) {}
}

#Preview("Confirmation") {
    let model = ComposeModel(db: DatabaseService(), circleId: UUID(),
                             author: Magazine.sample.pages[0].author!)
    model.previewResolved(url: "https://www.youtube.com/watch?v=62bIsvRcPv0",
                          title: "I Spent 3 Weeks Living Off-Grid in the Mountains")
    return ComposeView(model: model) {}
        .onAppear { model.previewMarkPosted() }
}
#endif
