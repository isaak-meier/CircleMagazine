//
//  CardGallery.swift
//  CircleMagazine
//
//  Every card the app can draw, in one scroll — plus every step of the compose
//  sheet. There is exactly one card view (`CardView`) and it branches on the
//  page's lead media, so "what are all the variations" has a finite answer and
//  this is it. When a card looks wrong in the edition, it looks wrong here too,
//  without needing a circle, a post, or a network round trip.
//
//  DEBUG only. Reachable on device from Account → Developer → Card gallery, and
//  in the canvas via the previews at the bottom.
//

#if DEBUG
import SwiftUI

struct CardGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    /// Which compose step is being shown, nil when the sheet is closed. One
    /// piece of state rather than a Bool per step — two sheets can't fight.
    @State private var composeStep: ComposeStep?

    // A frozen edition VM, so cards render their footer (comment / react /
    // reactors) exactly as the feed does. Nothing here fetches.
    private let issue = IssueViewModel.preview(.loaded(Magazine.sample))
    private let me = galleryUser("You")
    private let philly = galleryUser("Philly Bum Bum")

    var body: some View {
        VStack(spacing: 0) {
            Masthead(title: "Cards", trailing: AnyView(closeButton))
            ScrollView {
                LazyVStack(spacing: Style.Space.xl) {
                    composeSection
                    youtubeSection
                    instagramSection
                    linkSection
                    photoSection
                    edgeSection
                }
                .padding(.vertical, Style.Space.lg)
            }
        }
        .background(Style.chrome)
        .sheet(item: $composeStep) { step in
            ComposeView(model: step.model(author: me)) {}
        }
    }

    private var closeButton: some View {
        Button("Done") { dismiss() }.buttonStyle(.link)
    }

    // MARK: Compose

    private var composeSection: some View {
        section("Compose sheet") {
            VStack(alignment: .leading, spacing: Style.Space.sm) {
                ForEach(ComposeStep.allCases) { step in
                    Button(step.title) { composeStep = step }
                        .buttonStyle(.link)
                    Text(step.note).font(Style.stamp).foregroundStyle(Style.meta)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Style.Space.lg)
            .background(Style.paper, in: RoundedRectangle(cornerRadius: Style.cardRadius))
            .padding(.horizontal, Style.Space.md)
        }
    }

    // MARK: YouTube

    private var youtubeSection: some View {
        section("YouTube") {
            item("Newsprint plate — red rule, serif title, byline. The only treatment there is.") {
                card(youtubePage())
            }
            item("No fetched title — the plate shrinks to the chip, and the note is printed once") {
                card(youtubePage(title: nil))
            }
            item("No title and no caption — the plate is just the byline") {
                card(youtubePage(title: nil, caption: nil))
            }
            item("Your own post — the ⋯ delete menu appears in the plate") {
                card(youtubePage(author: me), canDelete: true)
            }
            item("Reacted to — the footer grows a cluster of faces") {
                card(youtubePage(reactors: ["Dave Slater", "kebaybay", "jmoney"]))
            }
        }
    }

    // MARK: Instagram — never plays inline, always a still that taps out

    private var instagramSection: some View {
        section("Instagram") {
            item("Reel — 9:16 poster cropped square, @handle badge, taps out to IG") {
                CardView(viewModel: CardViewModel(
                    previewing: .insta(id: "DZ30GywAbc7", kind: .reel), author: philly,
                    title: nil, caption: "first reel on Circle 🎬",
                    instaPoster: .direct(stockPhoto("reel")), handle: "infinite_mantra"),
                    issue: issue, me: me)
            }
            item("Post — square, sized to its own media like the reel") {
                CardView(viewModel: CardViewModel(
                    previewing: .insta(id: "DZXrc1uuezb", kind: .post), author: philly,
                    title: nil, caption: "saw this and thought of the group",
                    instaPoster: .direct(stockPhoto("post")), handle: "infinite_mantra"),
                    issue: issue, me: me)
            }
            item("Poster scrape missed — the gradient stands in, the card still works") {
                CardView(viewModel: CardViewModel(
                    previewing: .insta(id: "DZ30GywAbc7", kind: .reel), author: philly,
                    title: nil, caption: nil),
                    issue: issue, me: me)
            }
        }
    }

    // MARK: Links — anything with no player of its own

    private var linkSection: some View {
        section("Links") {
            item("With a cover image — og:image at its authored 1.91:1") {
                CardView(viewModel: CardViewModel(
                    previewingLink: URL(string: "https://www.theatlantic.com/x")!,
                    meta: .init(title: "The Quietest Place in America",
                                imageURL: stockPhoto("atlantic"), siteName: "The Atlantic"),
                    author: philly, caption: "had to share this one"),
                    issue: issue, me: me)
            }
            item("Headline only — no image is ordinary, not a failure") {
                CardView(viewModel: CardViewModel(
                    previewingLink: URL(string: "https://www.nytimes.com/y")!,
                    meta: .init(title: "A Very Long Headline That Runs To Three Lines Before The Card Decides It Has Had Quite Enough Of This",
                                imageURL: nil, siteName: "The New York Times"),
                    author: philly, caption: nil),
                    issue: issue, me: me)
            }
            item("Site published nothing — named by its host, provenance line dropped") {
                CardView(viewModel: CardViewModel(
                    previewingLink: URL(string: "https://example.com/a")!, meta: nil,
                    author: philly, caption: "trust me"),
                    issue: issue, me: me)
            }
        }
    }

    // MARK: Photos — a member's own picture

    private var photoSection: some View {
        section("Photos") {
            item("With a caption — the photo at its own shape, words underneath") {
                CardView(viewModel: CardViewModel(
                    previewingPhoto: stockPhoto("photo"), author: philly,
                    caption: "sunday, finally"),
                    issue: issue, me: me)
            }
            item("No caption — byline, photo, footer") {
                CardView(viewModel: CardViewModel(
                    previewingPhoto: stockPhoto("photo2"), author: philly,
                    caption: nil),
                    issue: issue, me: me)
            }
        }
    }

    // MARK: Edge cases — what a bad row looks like

    private var edgeSection: some View {
        section("Edge cases") {
            item("Raw video file — playback was never wired up (TODO in VideoCard)", height: 420) {
                card(page(media: media("video", url: "https://example.com/clip.mp4")))
            }
            item("Nothing renderable — the feed drops this page, so it should never ship",
                 height: 220) {
                card(page(media: media("audio", url: "https://example.com/clip.mp3")))
            }
        }
    }

    // MARK: Building blocks

    /// A card straight off the feed path: DB rows → CardViewModel → CardView, so
    /// what's on screen went through the same transform a real page does.
    private func card(_ magazinePage: MagazinePage, canDelete: Bool = false) -> some View {
        CardView(viewModel: CardViewModel(from: magazinePage, meId: me.id),
                 issue: issue, me: me,
                 onDelete: canDelete ? {} : nil)
    }

    private func youtubePage(title: String? = "I Spent 3 Weeks Living Off-Grid in the Mountains",
                             caption: String? = "This shit is SO DOPE!!",
                             author: User? = nil,
                             reactors: [String] = []) -> MagazinePage {
        page(title: title, caption: caption,
             media: media("video", url: "https://www.youtube.com/watch?v=62bIsvRcPv0"),
             author: author ?? philly,
             reactions: reactors.map { reaction(by: galleryUser($0)) })
    }

    private func page(title: String? = nil, caption: String? = nil, media: PageMedia,
                      author: User? = nil, reactions: [ReactionWithAuthor] = []) -> MagazinePage {
        MagazinePage(
            page: Page(id: UUID(), issueId: UUID(), submittedBy: author?.id,
                       title: title, caption: caption, createdAt: nil),
            pageMedia: [media], author: author ?? philly, reactions: reactions)
    }

    private func media(_ type: String, url: String) -> PageMedia {
        PageMedia(id: UUID(), pageId: nil, mediaUrl: url, mediaType: type, textContent: nil,
                  posterUrl: nil, posterFocus: nil, position: 0, createdAt: nil)
    }

    /// A stand-in photo off the open web. The gallery is DEBUG-only, and a card
    /// with a grey rectangle in it tells you nothing about the card.
    private func stockPhoto(_ seed: String) -> URL {
        URL(string: "https://picsum.photos/seed/\(seed)/900/1200")!
    }

    private func reaction(by user: User) -> ReactionWithAuthor {
        ReactionWithAuthor(
            reaction: Reaction(id: UUID(), pageId: UUID(), userId: user.id,
                               mediaPath: "gallery/reaction.jpg", createdAt: nil),
            author: user)
    }

    // MARK: Layout

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Style.Space.lg) {
            HStack(spacing: Style.Space.md) {
                Text(title.uppercased()).font(Style.eyebrow).tracking(1.8)
                    .foregroundStyle(Style.meta)
                Rectangle().fill(Style.rule).frame(height: 1)
            }
            .padding(.horizontal, Style.Space.md)
            content()
        }
    }

    /// One labelled specimen. `height` mirrors what the feed would give it — nil
    /// for the cards that size to their own media (`hugsItsMedia`), a fixed page
    /// for the ones that fill the viewport, so the gallery scrolls.
    @ViewBuilder
    private func item(_ note: String, height: CGFloat? = nil,
                      @ViewBuilder card: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Style.Space.xs) {
            Text(note).font(Style.stamp).foregroundStyle(Style.meta)
                .padding(.horizontal, Style.Space.md)
            card().frame(height: height)
        }
        .padding(.horizontal, Style.Space.md)
    }
}

// MARK: - Compose steps

/// Each step the compose sheet can be sitting on, seeded without a network call.
/// The sheet drives itself off `ComposeModel`, so staging the model is the whole
/// job — there's no separate "screen" to pick.
private enum ComposeStep: String, CaseIterable, Identifiable {
    case paste, youtube, reel, webLink, bareLink, photo, posted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste:    "1 · Paste — nothing staged yet"
        case .youtube:  "2 · YouTube link staged"
        case .reel:     "2 · Instagram reel staged"
        case .webLink:  "2 · Web link staged"
        case .bareLink: "2 · Web link, no metadata"
        case .photo:    "2 · Photo staged"
        case .posted:   "3 · Confirmation"
        }
    }

    var note: String {
        switch self {
        case .paste:    "Link field, the paste chip when the clipboard has one, and the type pills."
        case .youtube:  "Live card preview at a fixed height, note field, edition spine."
        case .reel:     "The poster is draggable here — this is the only preview that isn't inert."
        case .webLink:  "Chip says \"Linked\"; the card shows the scraped cover."
        case .bareLink: "Chip says \"No preview\"; the card names the link by its host."
        case .photo:    "Chip, live card, note field — the shape is decided by the photo's orientation, not the author."
        case .posted:   "Full-height page, no resize. Only links get the scheduled recap row."
        }
    }

    @MainActor
    func model(author: User) -> ComposeModel {
        let model = ComposeModel(db: DatabaseService(), circleId: UUID(), author: author)
        switch self {
        case .paste:
            break
        case .youtube:
            model.previewResolved(url: "https://www.youtube.com/watch?v=62bIsvRcPv0",
                                  title: "I Spent 3 Weeks Living Off-Grid in the Mountains")
        case .reel:
            model.previewResolved(url: "https://www.instagram.com/reels/DZ30GywAbc7/",
                                  title: nil,
                                  insta: .init(posterURL: URL(string: "https://picsum.photos/seed/reel/900/1600")!,
                                               handle: "infinite_mantra"))
        case .webLink:
            model.previewWebLink("https://www.theatlantic.com/x",
                                 meta: .init(title: "The Quietest Place in America",
                                             imageURL: URL(string: "https://picsum.photos/seed/atlantic/1200/628")!,
                                             siteName: "The Atlantic"))
        case .bareLink:
            model.previewWebLink("https://example.com/a", meta: nil)
        case .photo:
            // No bytes: nothing here posts, and the preview only wants a URL.
            model.stagePhoto(jpeg: Data(),
                             previewURL: URL(string: "https://picsum.photos/seed/photo/900/1200")!)
        case .posted:
            model.previewResolved(url: "https://www.youtube.com/watch?v=62bIsvRcPv0",
                                  title: "I Spent 3 Weeks Living Off-Grid in the Mountains")
            model.previewMarkPosted()
        }
        return model
    }
}

private func galleryUser(_ name: String) -> User {
    User(id: UUID(), username: name, bio: nil, avatarUrl: nil, role: nil,
         followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
}

#Preview("Card gallery") {
    CardGalleryView()
}
#endif
