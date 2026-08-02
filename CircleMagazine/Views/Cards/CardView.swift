//
//  CardView.swift
//  CircleMagazine
//
//

import SwiftUI
import AVKit
import PhotosUI   // the reaction fallback when there's no camera
import UIKit      // UIImage, on its way to JPEG bytes

struct CardView: View {
    let viewModel: CardViewModel
    /// The edition's VM — supplies comments + poster URLs. Nil in the compose
    /// preview, where the bar is a static mockup and the poster is a direct URL.
    var issue: IssueViewModel? = nil
    var me: User? = nil
    /// True for the card the feed is snapped to — drives YouTube autoplay.
    var isActive: Bool = false
    /// Deletes this page (feed supplies the DB call + refresh). Offered only on
    /// the viewer's own posts, matching the DB's "delete own pages" rule.
    var onDelete: (() async -> Void)? = nil
    /// Compose only: dragging the reel poster reports a new crop focus. Nil in
    /// the feed, where the poster is static and taps out to Instagram.
    var onPosterFocusChange: ((Double) -> Void)? = nil

    @State private var showComments = false
    @State private var confirmingDelete = false
    /// The photo being viewed full screen, if any.
    @State private var fullscreenPhoto: MediaRef?
    /// Where the reaction photo is coming from — nil when nothing is open. One
    /// state rather than a Bool per surface, so two pickers can't both be up.
    @State private var capture: ReactionCapture?
    @State private var pickedReaction: PhotosPickerItem?
    @State private var showingReactions = false

    /// How the viewer supplies a reaction photo. Camera when there is one and
    /// we're allowed it; the library otherwise (every simulator, and any device
    /// where camera access was denied).
    private enum ReactionCapture { case camera, library }

    /// The card's photo, when it has one — what a tap opens full screen.
    private var photo: MediaRef? {
        if case .image(let ref)? = viewModel.media.first { return ref }
        return nil
    }

    /// Whether this card can be acted on at all. False in the compose preview,
    /// which renders a CardView for a post that doesn't exist yet.
    private var interactive: Bool { issue != nil && me != nil }
    private var canDelete: Bool { onDelete != nil && me?.id == viewModel.author?.id }

    var body: some View {
        VStack(spacing: 0) {
            content
            // Always drawn, even in the compose preview, where there's nothing
            // to act on: the footer is the only thing giving the newsprint plate
            // a bottom margin, so a card without one sits flush against its own
            // clipped corner. The preview is meant to be the card, so it gets
            // the row too — just dead.
            CardFooter(card: viewModel,
                       isReacting: issue?.reactingPageId == viewModel.id,
                       onComment: { showComments = true },
                       onReact: { capture = CameraPicker.canUseCamera ? .camera : .library },
                       onRemoveReaction: { Task { await issue?.unreact(pageId: viewModel.id) } },
                       onOpenReactions: { showingReactions = true })
                .allowsHitTesting(interactive)
                // Hidden rather than merely untappable — VoiceOver offering a
                // React button that does nothing is worse than no button.
                .accessibilityHidden(!interactive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Style.paper)
        .clipShape(RoundedRectangle(cornerRadius: Style.cardRadius))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
        .sheet(isPresented: $showComments) {
            if let issue {
                CommentsView(model: issue.commentsVM(for: viewModel.id))
            }
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await onDelete?() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed from the edition for everyone. This can't be undone.")
        }
        .fullScreenCover(item: $fullscreenPhoto) { ref in
            PhotoViewer(ref: ref, issue: issue)
        }
        .fullScreenCover(isPresented: presenting(.camera)) {
            CameraPicker { image in Task { await react(with: image) } }
        }
        .photosPicker(isPresented: presenting(.library), selection: $pickedReaction,
                      matching: .images, photoLibrary: .shared())
        // Decoding lives here, not in the VM: UIImage and PhotosPickerItem are UI
        // types, and keeping them out is what lets `react` be tested with bytes.
        //
        // An unstructured Task, not `.task(id:)`: reacting refreshes the edition,
        // which rebuilds this card — and a view-bound task gets cancelled when
        // that happens, mid-upload. Same reason `onDelete` uses one.
        .onChange(of: pickedReaction) { _, picked in
            guard let picked else { return }
            pickedReaction = nil
            Task { await react(withPicked: picked) }
        }
        .fullScreenCover(isPresented: $showingReactions) {
            ReactionViewer(reactions: viewModel.reactions, issue: issue)
        }
    }

    /// A Bool binding for one capture surface. Set-to-false is a dismissal, so
    /// closing either picker clears the state; only the tap sets it.
    private func presenting(_ mode: ReactionCapture) -> Binding<Bool> {
        Binding(get: { capture == mode }, set: { if !$0 { capture = nil } })
    }

    private func react(with image: UIImage) async {
        capture = nil
        guard let jpeg = image.reactionJPEG() else { return }
        await issue?.react(pageId: viewModel.id, jpeg: jpeg)
    }

    private func react(withPicked item: PhotosPickerItem) async {
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: raw) else { return }
        await react(with: image)
    }

    // ⋯ menu, shown in the poster row. Native Menu, same as the Circles
    // join/create menu.
    private var cardMenu: some View {
        Menu {
            Button("Delete Post", role: .destructive) { confirmingDelete = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Style.meta)
                .frame(width: 30, height: 30, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var content: some View {
        // ponytail: .first — video-only cards; switch on the full array if mixed cards appear
        switch viewModel.media.first {
        case .video(let source, let instaPoster, let handle, let focus):
            VideoCard(source: source, author: viewModel.author, caption: viewModel.caption, title: viewModel.title, isActive: isActive, trailingAccessory: canDelete ? AnyView(cardMenu) : nil, instaPoster: instaPoster, instaHandle: handle, issue: issue, instaFocus: focus, onInstaFocusChange: onPosterFocusChange)
        case .link(let preview):
            LinkCard(preview: preview, author: viewModel.author, caption: viewModel.caption,
                     issue: issue, trailingAccessory: canDelete ? AnyView(cardMenu) : nil)
        default:                 standardCard   // image / fallback / empty
        }
    }

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle
            if let author = viewModel.author {
                AuthorRow(author: author)
                    .padding(.horizontal, Style.Space.lg)
                    .padding(.bottom, Style.Space.md)
            }
            // Full-bleed: the card is already clipped to its own radius, so the
            // photo runs to the edges instead of sitting inset on a page.
            CardMediaRegion(card: viewModel, issue: issue)
                // The card crops the photo to fill; tapping shows the whole
                // frame. A bare gesture is invisible to VoiceOver and to UI
                // automation, so it says what it is.
                .contentShape(Rectangle())
                .onTapGesture { fullscreenPhoto = photo }
                .accessibilityElement()
                .accessibilityLabel("Photo")
                .accessibilityHint("Opens full screen")
                .accessibilityAddTraits(.isButton)
            // The author's words under their photo, set like a magazine caption.
            // Video cards carry this in their own plate; without it here a photo
            // post would silently drop everything the author wrote.
            if let caption = viewModel.caption, !caption.isEmpty {
                Text(caption)
                    .font(Style.body).foregroundStyle(Style.ink)
                    .padding(.horizontal, Style.Space.lg)
                    .padding(.top, Style.Space.md)
            }
            Spacer(minLength: 0)
        }
    }

    private var handle: some View {
        Capsule().fill(Style.rule)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10).padding(.bottom, 6)
    }
}

// MARK: - Author row

private struct AuthorRow: View {
    let author: User

    var body: some View {
        HStack(spacing: 9) {
            Avatar(user: author, diameter: 32)
            Text(author.username).font(Style.byline).foregroundStyle(Style.ink)
        }
    }
}

// MARK: - Media region

private struct CardMediaRegion: View {
    let card: CardViewModel
    /// Supplies signed URLs for stored photos. Nil in the compose preview, where
    /// the ref is already `.direct`.
    var issue: IssueViewModel? = nil

    @ViewBuilder
    var body: some View {
        if case .image(let ref) = card.media.first {
            PhotoMedia(ref: ref, issue: issue)
        }
    }
}

/// A photo page, shown at the photo's own aspect ratio — the same deal every
/// other medium now gets.
///
/// It used to be `Color.clear` filling the card with the photo `scaledToFill`
/// on top, which crops rather than letterboxes. That only works when something
/// has already given the card a height: `Color.clear` has none of its own. The
/// feed does (`feedCardFrame()`), the compose preview doesn't, so a staged
/// photo collapsed to a sliver and the crop ate it.
private struct PhotoMedia: View {
    let ref: MediaRef
    var issue: IssueViewModel?

    @State private var url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            // Nothing knows the photo's shape until the bytes land, so the slot
            // is portrait — the common camera-roll shape — and the card resizes
            // once, when the real one arrives.
            Rectangle().fill(Style.rule).aspectRatio(3.0 / 4.0, contentMode: .fit)
        }
        .frame(maxWidth: .infinity)
        // Signed URLs expire, so resolve on appear rather than once at build
        // time — a card scrolled back to after an hour still loads.
        .task(id: ref.id) { url = await ref.resolve(with: issue) }
    }
}

/// A photo on its own, filling the screen. The card already shows the whole
/// frame, so this is about size rather than crop — a detail you had to squint
/// at in the edition, at the size it was shot.
private struct PhotoViewer: View {
    let ref: MediaRef
    var issue: IssueViewModel?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
            FullPhoto(ref: ref, issue: issue)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .overlay(alignment: .topTrailing) { ViewerCloseButton() }
        // Tap-anywhere is the gesture people reach for, but it's invisible to
        // VoiceOver and to anyone who doesn't guess — so there's a real button.
        .accessibilityAction(.escape) { dismiss() }
    }
}

/// Everyone's reactions to one card, one per page, each named. The photos are
/// the point — the cluster shows whose they are, this shows what they took.
private struct ReactionViewer: View {
    let reactions: [ReactionViewModel]
    var issue: IssueViewModel?

    @Environment(\.dismiss) private var dismiss
    @State private var shown: UUID?

    var body: some View {
        ZStack {
            Color.black
            TabView(selection: $shown) {
                ForEach(reactions) { reaction in
                    VStack(spacing: Style.Space.lg) {
                        FullPhoto(ref: reaction.photo, issue: issue)
                        if let author = reaction.author {
                            Text(author.username)
                                .font(Style.byline).foregroundStyle(.white)
                        }
                    }
                    .padding(.vertical, Style.Space.xxl)
                    .tag(Optional(reaction.id))
                }
            }
            .tabViewStyle(.page)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) { ViewerCloseButton() }
        .accessibilityAction(.escape) { dismiss() }
        .onAppear { shown = shown ?? reactions.first?.id }
    }
}

/// One stored photo, signed and shown whole. Fit, not fill: cards crop, viewers
/// don't — that's what a viewer is for.
private struct FullPhoto: View {
    let ref: MediaRef
    var issue: IssueViewModel?

    @State private var url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            ProgressView().tint(.white)
        }
        // Signed afresh: the card's URL may have expired while it sat on screen.
        .task(id: ref.id) { url = await ref.resolve(with: issue) }
    }
}

private struct ViewerCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.45), in: SwiftUI.Circle())
        }
        .accessibilityLabel("Close")
        .padding(.top, Style.Space.xl)
        .padding(.trailing, Style.Space.lg)
    }
}

extension MediaRef {
    /// The loadable URL for this ref: a stored path is signed through the issue
    /// (the bucket is private), a direct URL is already loadable.
    func resolve(with issue: IssueViewModel?) async -> URL? {
        switch self {
        case .direct(let url):  url
        case .stored(let path): await issue?.signedURL(path: path)
        }
    }
}


#if DEBUG
#Preview("Card") {
    CardView(viewModel: CardViewModel(from: Magazine.sample.pages[0]))
        .frame(height: 600)
        .padding()
        .background(Style.chrome)
}
#endif
