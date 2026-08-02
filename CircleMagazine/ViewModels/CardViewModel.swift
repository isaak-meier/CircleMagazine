//
//  Card.swift
//  CircleMagazine
//
//  A card is a Page: an author's post carrying media. CardViewModel transforms
//  each raw PageMedia row into a CardMediaViewModel the views render directly.

import Foundation

struct CardViewModel: Identifiable {
    let id: UUID
    let media: [CardMediaViewModel]     // the page's media, in position order
    let author: User?
    let title: String?
    let caption: String?

    /// Who reacted, oldest first, ready to render as faces.
    let reactions: [ReactionViewModel]

    /// `meId` is the viewer, so a card knows which reaction is theirs. Nil in
    /// previews and the compose sheet, where there's no one to be.
    init(from page: MagazinePage, meId: UUID? = nil) {
        self.id = page.page.id
        self.author = page.author
        self.title = page.page.title
        self.caption = page.page.caption
        self.media = page.pageMedia
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            .map { CardMediaViewModel($0, pageTitle: page.page.title) }
        self.reactions = page.reactions.map {
            ReactionViewModel(id: $0.id, author: $0.author,
                              photo: .stored(path: $0.reaction.mediaPath),
                              isMine: $0.reaction.userId == meId)
        }
    }

    /// Whether there's anything to draw. False for a page with no media rows, and
    /// for one whose only rows are `.fallback` — both render as blank paper, so
    /// the feed leaves them out.
    var hasRenderableMedia: Bool {
        media.contains {
            switch $0 {
            case .image, .video, .link: true
            case .fallback:             false
            }
        }
    }

    /// The viewer's own reaction, if they've made one. Drives whether the React
    /// control offers "react" or "retake / remove".
    var myReaction: ReactionViewModel? { reactions.first(where: \.isMine) }

    /// What VoiceOver reads for the cluster. Here rather than in the view so the
    /// wording is testable — and because the cluster deliberately shows no
    /// number, this sentence is the only place a count is ever spoken.
    var reactionSummary: String? {
        let names = reactions.compactMap { $0.author?.firstName }
        switch names.count {
        case 0:  return reactions.isEmpty ? nil : "Reactions"
        case 1:  return "\(names[0]) reacted"
        case 2:  return "\(names[0]) and \(names[1]) reacted"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) others reacted"
        }
    }

    /// What the card leads with. The feed runs through these in order, so the
    /// case order here IS the edition's running order — move a case to move a
    /// whole section.
    enum Medium: CaseIterable {
        case youtube, instagram, link, other
    }

    /// Only the lead item decides, same as everything else about a card's shape.
    var medium: Medium {
        switch media.first {
        case .video(.youtube, _, _, _): .youtube
        case .video(.insta, _, _, _):   .instagram
        case .link:                     .link
        default:                        .other
        }
    }

    /// The card is sized by its media, not by the viewport: a YouTube video is
    /// 16:9 and a tall reel crops to its poster window, so both are shown at
    /// that shape and centred rather than stretched to fill the page. Stretching
    /// a 16:9 video to a portrait card can only crop, and it crops through
    /// burned-in captions and the player's own chrome.
    var hugsItsMedia: Bool {
        switch media.first {
        case .video(.youtube, _, _, _): true
        // Both Instagram kinds render square, so both hug.
        case .video(.insta, _, _, _):   true
        // A link card is a headline and a thumbnail — stretching it to a full
        // page would be mostly empty paper.
        case .link:  true
        // A photo is shown at the shape it was shot in, same as the video
        // above it. Filling a fixed page could only crop it.
        case .image: true
        default:     false
        }
    }

    /// Compose live preview — a card that doesn't exist in the DB yet. For an
    /// insta preview, `instaPoster`/`handle` carry the freshly-scraped frame so
    /// the preview matches the feed card (no re-host round trip needed yet).
    init(previewing source: VideoSource, author: User?, title: String?, caption: String?,
         instaPoster: MediaRef? = nil, handle: String? = nil, focus: Double = 0.5) {
        self.id = UUID()
        self.media = [.video(source, instaPoster, handle: handle, focus: focus)]
        self.author = author
        self.title = title
        self.caption = caption
        self.reactions = []   // nothing to react to until it's posted
    }

    /// Compose live preview for a pasted link. `meta` is whatever the scrape
    /// found, nil included — a page that publishes nothing still previews, as
    /// its own domain, because "no preview" must not read as "can't post".
    ///
    /// `title` mirrors what `post()` will write to the page's title column, so
    /// what the author approves is what the edition shows.
    init(previewingLink url: URL, meta: OpenGraph.Meta?, author: User?,
         caption: String?) {
        let preview = LinkPreview(destination: url, meta: meta)
        self.id = UUID()
        self.media = [.link(preview)]
        self.author = author
        self.title = preview.title
        self.caption = caption
        self.reactions = []   // nothing to react to until it's posted
    }

    /// Compose live preview for a picked photo — the bytes are already on the
    /// device, so the ref is `.direct` and the preview needs no signing.
    init(previewingPhoto url: URL, author: User?, caption: String?) {
        self.id = UUID()
        self.media = [.image(.direct(url))]
        self.author = author
        self.title = nil
        self.caption = caption
        self.reactions = []   // nothing to react to until it's posted
    }
}

/// One person's reaction to a card, ready to render: whose it is, the photo, and
/// whether it's the viewer's own.
struct ReactionViewModel: Identifiable {
    let id: UUID
    /// Nil when that user row didn't come back — someone who left the circle.
    /// Their face can't be drawn, so the cluster drops them rather than showing
    /// a blank circle.
    let author: User?
    let photo: MediaRef
    let isMine: Bool
}

/// Where an image the card shows comes from — a member's photo or an Instagram
/// cover frame, same two answers either way: a path in our private bucket (the
/// feed, which has to sign it) or a directly-loadable URL (a compose preview,
/// where the bytes are local or freshly scraped and no round trip is needed).
enum MediaRef: Equatable, Identifiable {
    case stored(path: String)
    case direct(URL)

    /// The underlying object. Views key their signing `task` on this so a URL is
    /// re-signed when the object changes and not on every re-render — signatures
    /// expire, so it can't just be resolved once at build time.
    var id: String {
        switch self {
        case .stored(let path): path
        case .direct(let url):  url.absoluteString
        }
    }
}

/// A shared link, ready to render. This is where scraped metadata stops being
/// "whatever the site published" and becomes something the view can lay out
/// without checking anything: the title is always present, the host is always
/// present, and the only question left is whether there's an image.
///
/// Built two ways — from a stored page (feed) or from a fresh scrape (compose
/// preview) — and both land here, so the preview can't drift from the card.
struct LinkPreview: Equatable {
    /// Where tapping the card goes. The link as pasted, never the scraped page's
    /// canonical URL: the member shared this one.
    let destination: URL
    /// The headline. Never empty — a page that publishes no metadata at all
    /// still reads as its own domain rather than as a blank card.
    let title: String
    /// "theatlantic.com" — the provenance line, and the one thing a reader needs
    /// to judge a link before tapping it.
    let host: String
    /// The scraped cover image. Nil is ordinary, not a failure.
    let image: MediaRef?

    /// The feed's route in: the title was scraped at post time and stored on the
    /// page, the image re-hosted into the circle's bucket.
    init(destination: URL, title: String?, image: MediaRef?) {
        self.destination = destination
        self.host = Self.host(of: destination)
        // Falls back to the host so the card always has a line of type. An
        // empty stored title counts as absent.
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = (trimmed?.isEmpty == false ? trimmed! : self.host)
        self.image = image
    }

    /// Compose's route in: a scrape that may have found nothing. Site name sits
    /// between title and host because a site that publishes only `og:site_name`
    /// still names itself better than its domain does.
    init(destination: URL, meta: OpenGraph.Meta?) {
        self.init(destination: destination,
                  title: meta?.title ?? meta?.siteName,
                  image: meta?.imageURL.map(MediaRef.direct))
    }

    /// "www." is noise on a provenance line — every reader mentally strips it.
    private static func host(of url: URL) -> String {
        let host = url.host()?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// One renderable piece of a card, transformed from a raw `PageMedia` row.
/// Text/audio are parked — those rows land on `.fallback`.
enum CardMediaViewModel {
    /// A photo. Stored rows carry a bucket path, never a URL: the bucket is
    /// private, so the view signs it when the card appears.
    case image(MediaRef)
    // insta carries its re-hosted poster + @handle + crop focus; nil/center for YouTube.
    case video(VideoSource, MediaRef?, handle: String?, focus: Double)
    /// A shared link with no player of its own — an article, a shop, a gist.
    case link(LinkPreview)
    case fallback(CardMediaError?)

    /// `pageTitle` is the page's own title column, which is where a scraped
    /// headline is stored (same column YouTube's title lands in) — a link row
    /// needs it to build its preview, so it's threaded down from the page.
    init(_ media: PageMedia, pageTitle: String? = nil) {
        guard let raw = media.mediaUrl, !raw.isEmpty else {
            self = .fallback(CardMediaError.invalidURL)
            return
        }
        switch media.mediaType {
            // A photo's media_url is a storage path, not a URL — don't try to
            // parse it as one.
            case "image": self = .image(.stored(path: raw))
            case "video":
                if let url = URL(string: raw), let videoSource = VideoSource(url) {
                    let poster = media.posterUrl.map(MediaRef.stored)
                    self = .video(videoSource, poster, handle: media.textContent,
                                  focus: media.posterFocus ?? 0.5)
                } else {
                    self = .fallback(CardMediaError.invalidURL)
                }
            // Everything that isn't a player: stored as "article", the type the
            // schema already allowed.
            case "article":
                if let url = URL(string: raw), url.host() != nil {
                    self = .link(LinkPreview(destination: url, title: pageTitle,
                                             image: media.posterUrl.map(MediaRef.stored)))
                } else {
                    self = .fallback(CardMediaError.invalidURL)
                }
            default: self = .fallback(nil)
        }
    }
}
enum CardMediaError: LocalizedError {
    case invalidURL
    var errorDescription: String? { "The url could not be parsed" }
}
