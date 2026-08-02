//
//  Supabase.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/16/26.
//

import Foundation
import Observation
import Supabase
import os

private let oembedLog = Logger(subsystem: "CircleMagazine", category: "oembed")

enum JoinError: LocalizedError {
  case badCode
  var errorDescription: String? { "No circle found with that invite code." }
}

@MainActor
@Observable
class DatabaseService {   // not final: tests subclass it to spy on writes
  let supabase = SupabaseClient(
    supabaseURL: Config.supabaseURL,
    supabaseKey: Config.supabaseAnonKey
  )

  /// `@MainActor` + approachable concurrency would give this an *isolated*
  /// deinit, which traps if the last reference is dropped off the main actor —
  /// exactly what happens when a test suite struct holding one is destroyed
  /// (the test target has no MainActor default isolation). Nothing here needs
  /// the main actor to tear down; the client releases fine from any thread.
  nonisolated deinit {}

  // MARK: - Auth

  /// The session events the account layer acts on, narrowed from Supabase's
  /// stream. Wrapping it here is what keeps `AccountManager` off the SDK — a
  /// test can subclass and hand back a stream it drives by hand.
  enum AuthChange {
    /// Launch/restore. `hasSession` false means nobody is signed in.
    case restored(hasSession: Bool)
    case signedOut
  }

  /// Cancels its upstream task when the consumer stops iterating.
  func authChanges() -> AsyncStream<AuthChange> {
    AsyncStream { continuation in
      let task = Task {
        for await change in supabase.auth.authStateChanges {
          switch change.event {
          case .initialSession: continuation.yield(.restored(hasSession: change.session != nil))
          case .signedOut:      continuation.yield(.signedOut)
          default: break   // .signedIn is driven explicitly by the sign-in flow
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Emails a one-time code, creating the auth user if this address is new.
  func sendOTP(email: String) async throws {
    try await supabase.auth.signInWithOTP(email: email)   // shouldCreateUser defaults true
  }

  func verifyOTP(email: String, code: String) async throws {
    try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
  }

  func signOut() async throws {
    try await supabase.auth.signOut()
  }

  func currentUserId() async throws -> UUID {
    try await supabase.auth.session.user.id
  }

  /// The signed-in user's profile row — nil when the auth user exists but
  /// hasn't picked a username yet (mid-signup).
  func currentProfile() async throws -> User? {
    let uid = try await currentUserId()
    let rows: [User] = try await supabase.from("users")
      .select().eq("id", value: uid.uuidString).limit(1).execute().value
    return rows.first
  }

  func createProfile(userId: UUID, username: String) async throws {
    try await supabase.from("users").insert(UserInsert(id: userId, username: username)).execute()
  }

  // MARK: - Reads

  func queryUsers() async -> [User] {
    do {
      let users: [User] = try await supabase.from("users").select().execute().value
      return users
    } catch {
      print("Users fetch from supabase failed with \(error)")
      fatalError()
    }
  }

  func queryIssues() async {
    do {
      let issues: [Issue] = try await supabase.from("issues").select().execute().value
      print("Fetched \(issues.count) issues:")
      for issue in issues {
        print(issue)
      }
    } catch {
      print("Issues fetch from supabase failed with \(error)")
    }
  }

  /// The circle's live issue with its pages (ordered) and each page's widgets
  /// (ordered by position), or **nil during the compose phase** — nothing is
  /// live, which is a normal half of the week, not a failure.
  /// could be optimzed for multiple async server calls TODO
  /// Debug: read the newest edition whatever its publish date, so the open draft
  /// is what the feed shows. Liveness is derived from `publish_date`, so without
  /// this a submission isn't readable until the Sunday it opens — which makes a
  /// post impossible to eyeball while building. Off ⇒ ordinary behaviour.
  static let showDraftKey = "debug.showDraftEdition"
  static var isShowingDraft: Bool { UserDefaults.standard.bool(forKey: showDraftKey) }

  func fetchCurrentIssue(circleId: UUID) async throws -> Magazine? {

    var query = supabase.from("issues")
      .select().eq("circle_id", value: circleId.uuidString)
    // Ordering by publish_date descending already puts the draft first, so the
    // only difference is whether we keep it.
    if !Self.isShowingDraft {
      query = query.lt("publish_date", value: Issue.liveCutoff())
    }
    let issues: [Issue] = try await query
      .order("publish_date", ascending: false).limit(1).execute().value
    guard let issue = issues.first else { return nil }

    let pages: [Page] = try await supabase.from("pages")
      .select().eq("issue_id", value: issue.id.uuidString)
      .order("created_at", ascending: true).execute().value
    // An issue with no pages yet is a valid empty edition (a draft before
    // anyone posts), not an error — hand it back so the feed shows its empty
    // state rather than the "something went wrong" screen.
    guard !pages.isEmpty else { return Magazine(issue: issue, pages: []) }

    // One round trip for all media, then group in memory. A page without media
    // just renders its fallback, so empty media is fine — no guard.
    let pageIds = pages.map(\.id.uuidString)
    let media: [PageMedia] = try await supabase.from("page_media")
      .select().in("page_id", values: pageIds)
      .order("position", ascending: true).execute().value
    let byPage = Dictionary(grouping: media, by: \.pageId)

    // Reactions for the whole edition in one round trip, same as media above —
    // a per-card fetch would be an N+1 against a feed that shows many cards.
    let reactions: [Reaction] = try await supabase.from("reactions")
      .select().in("page_id", values: pageIds)
      .order("created_at", ascending: true).execute().value
    let reactionsByPage = Dictionary(grouping: reactions, by: \.pageId)

    // People — page submitters AND reactors, in the round trip that was already
    // happening. `users` is readable by any signed-in member, so a reactor who
    // didn't write a page still resolves.
    let peopleIds = Array(Set(pages.compactMap(\.submittedBy?.uuidString))
      .union(reactions.map(\.userId.uuidString)))
    let people: [User] = peopleIds.isEmpty ? [] : try await supabase.from("users")
      .select().in("id", values: peopleIds).execute().value
    let byId = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })

    let result = pages.map { page in
      MagazinePage(
        page: page,
        pageMedia: byPage[page.id] ?? [],
        author: page.submittedBy.flatMap { byId[$0] },
        reactions: (reactionsByPage[page.id] ?? []).map {
          ReactionWithAuthor(reaction: $0, author: byId[$0.userId])
        })
    }
    return Magazine(issue: issue, pages: result)
  }

  /// Cheap staleness probe — just the issue's id, no pages/media.
  func currentIssueId(circleId: UUID) async throws -> UUID? {
    let issues: [Issue] = try await supabase.from("issues")
      .select().lt("publish_date", value: Issue.liveCutoff()).eq("circle_id", value: circleId.uuidString)
      .order("publish_date", ascending: false).limit(1).execute().value
    return issues.first?.id
  }

  /// The edition a submission belongs in: **always the open draft**, created on
  /// this circle's first submission of the week.
  ///
  /// Never the live edition. A published issue is finished — it's what the
  /// circle is reading, and appending to it would make new pages materialise
  /// inside an edition people already went through. Posting during the read
  /// phase means "put this in next week's issue", which is the draft.
  ///
  /// (This deliberately ignores `currentIssueId`. It used to consult it first,
  /// which was harmless only because publishing was manual and rare — with
  /// derived liveness there is always a live edition after week one, so that
  /// branch would have swallowed every submission forever.)
  func issueIdForSubmission(circleId: UUID) async throws -> UUID {
    if let draft = try await draftIssueId(circleId: circleId) { return draft }
    do {
      return try await createDraftIssue(circleId: circleId)
    } catch {
      // Lost the race to another member's first submission — the one-edition-
      // per-week index rejected our insert, so post into the draft they just made.
      guard let draft = try await draftIssueId(circleId: circleId) else { throw error }
      return draft
    }
  }

  /// Opens this circle's next edition, stamped with the Saturday it closes on.
  /// Separate from `issueIdForSubmission` so the orchestration above (and its
  /// lost-the-race branch) can be exercised without a live database.
  func createDraftIssue(circleId: UUID) async throws -> UUID {
    let created: Issue = try await supabase.from("issues")
      .insert(IssueInsert(circleId: circleId,
                          publishDate: Issue.publishDate(for: EditionCountdown.publishDay())))
      .select().single().execute().value
    return created.id
  }

  /// The circle's open edition — the soonest one whose closing Saturday hasn't
  /// passed yet. The mirror image of the live filter, so every issue is on
  /// exactly one side of the cutoff and no edition can be both or neither.
  func draftIssueId(circleId: UUID) async throws -> UUID? {
    let issues: [Issue] = try await supabase.from("issues")
      .select().gte("publish_date", value: Issue.liveCutoff()).eq("circle_id", value: circleId.uuidString)
      .order("publish_date", ascending: true).limit(1).execute().value
    return issues.first?.id
  }

  /// Circles the user belongs to, each with its full member list (for bubble
  /// size and the sheet's avatar row).
  /// ponytail: loads every member of every circle — fine at friend-group
  /// scale; switch to a count aggregate if circles get big.
  func fetchCircles(memberOf userId: UUID) async throws -> [CircleSummary] {
    let mine: [CircleMember] = try await supabase.from("circle_members")
      .select().eq("user_id", value: userId.uuidString).execute().value
    let circleIds = mine.map(\.circleId.uuidString)
    guard !circleIds.isEmpty else { return [] }

    let circles: [Circle] = try await supabase.from("circles")
      .select().in("id", values: circleIds).execute().value
    let members: [CircleMember] = try await supabase.from("circle_members")
      .select().in("circle_id", values: circleIds).execute().value

    let userIds = Array(Set(members.map(\.userId.uuidString)))
    let users: [User] = userIds.isEmpty ? [] : try await supabase.from("users")
      .select().in("id", values: userIds).execute().value
    let usersById = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
    let membersByCircle = Dictionary(grouping: members, by: \.circleId)

    return circles.map { circle in
      CircleSummary(circle: circle,
                    members: (membersByCircle[circle.id] ?? []).compactMap { usersById[$0.userId] })
    }
  }

  // MARK: - Writes

  /// Creates a video post. For a YouTube URL we look up the real video title via
  /// oEmbed and store it on the page, so the feed can read `pages.title` without
  /// any per-render network calls. Title lookup is best-effort — a failure just
  /// leaves the title nil rather than blocking the post.
  ///
  /// Instagram can't play inline, so `insta` carries the pre-scraped cover frame
  /// URL + @handle (from compose): we download that still and re-host it in the
  /// circle's folder of the `media` bucket, storing its path in poster_url and
  /// the handle in text_content. A failed re-host just leaves poster_url nil —
  /// the card falls back to its gradient rather than blocking the post.
  @discardableResult
  func createVideoPost(issueId: UUID, circleId: UUID, authorId: UUID, videoURL: URL, caption: String?,
                       insta: InstagramEmbed.Meta? = nil, posterFocus: Double? = nil) async throws -> Page {
    var title: String?
    if case .youtube(let id)? = VideoSource(videoURL) {
      title = await YouTubeOEmbed.title(forVideoID: id)
    }
    let page: Page = try await supabase.from("pages")
      .insert(PageInsert(issueId: issueId, submittedBy: authorId, title: title,
                         caption: caption, captionStyle: .newsprintKicker))
      .select().single().execute().value

    var posterPath: String?
    if let insta, case .insta(let id, _)? = VideoSource(videoURL) {
      posterPath = try? await rehostImage(from: insta.posterURL, circleId: circleId, named: id)
    }
    try await supabase.from("page_media")
      .insert(PageMediaInsert(pageId: page.id, mediaUrl: videoURL.absoluteString,
                              mediaType: "video", textContent: insta?.handle,
                              posterUrl: posterPath,
                              posterFocus: insta != nil ? posterFocus : nil, position: 0))
      .execute()

    // The author's note becomes the post's first comment. Best-effort: the page
    // already exists, so a comment hiccup shouldn't fail the whole post.
    if let caption {
      _ = try? await supabase.from("comments")
        .insert(CommentInsert(pageId: page.id, userId: authorId, body: caption))
        .execute()
    }
    return page
  }

  /// Every uploaded byte lives here: members' photos and re-hosted reel covers
  /// alike. Private — reads go through `signedURL`.
  static let mediaBucket = "media"

  /// Storage paths are `{circleId}/{name}`, and **the prefix is the access
  /// control**: the bucket's policy only lets you touch a folder whose name is a
  /// circle you belong to. Every upload has to go through here so nothing can
  /// land outside a circle's folder by accident.
  ///
  /// Lowercased on purpose — Swift's `uuidString` is uppercase but Postgres
  /// renders `uuid::text` lowercase, so an uppercase folder would compare
  /// unequal to its own circle and the policy would deny every read.
  private static func mediaPath(circleId: UUID, name: String) -> String {
    "\(circleId.uuidString.lowercased())/\(name)"
  }

  /// Download an image someone else is hosting — an Instagram cover frame, a
  /// link's og:image — and re-host it in this circle's folder (upsert, so
  /// re-posting the same thing replaces its file). Returns the stored path.
  ///
  /// Re-hosted rather than hot-linked because the far end's URL expires, blocks
  /// hot-linking, or changes what it serves; a stored copy also means the feed
  /// isn't announcing every reader to a third party.
  private func rehostImage(from remote: URL, circleId: UUID, named name: String) async throws -> String {
    let (data, _) = try await URLSession.shared.data(from: remote)
    return try await upload(data, circleId: circleId, name: "\(name).jpg")
  }

  /// Put a JPEG in a circle's folder and hand back its stored path.
  private func upload(_ data: Data, circleId: UUID, name: String) async throws -> String {
    let path = Self.mediaPath(circleId: circleId, name: name)
    try await supabase.storage.from(Self.mediaBucket)
      .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
    return path
  }

  /// A short-lived signed URL for a stored object — the bucket is private, so
  /// the feed regenerates one each time a card appears (cheap, and never a dead
  /// link since it's our bucket). Signing is itself gated by the bucket policy,
  /// so a path belonging to a circle you left won't sign.
  func signedURL(path: String) async -> URL? {
    try? await supabase.storage.from(Self.mediaBucket).createSignedURL(path: path, expiresIn: 3600)
  }

  /// Creates a photo post: upload the JPEG into the circle's folder, then a page
  /// whose single media row is that stored path (`media_type: "image"`). The
  /// path is stored, not a URL — the bucket is private, so the feed signs it at
  /// render time.
  ///
  /// Ordering is deliberate: upload first, so a storage failure means no page
  /// at all rather than a page with nothing in it. Unlike the poster re-host —
  /// which is decoration a card can live without — the photo IS the post.
  @discardableResult
  func createPhotoPost(issueId: UUID, circleId: UUID, authorId: UUID, jpeg: Data,
                       caption: String?) async throws -> Page {
    let path = try await upload(jpeg, circleId: circleId, name: "\(UUID().uuidString).jpg")

    let page: Page = try await supabase.from("pages")
      .insert(PageInsert(issueId: issueId, submittedBy: authorId, title: nil,
                         caption: caption, captionStyle: .newsprintKicker))
      .select().single().execute().value
    try await supabase.from("page_media")
      .insert(PageMediaInsert(pageId: page.id, mediaUrl: path, mediaType: "image", position: 0))
      .execute()

    if let caption {
      _ = try? await supabase.from("comments")
        .insert(CommentInsert(pageId: page.id, userId: authorId, body: caption))
        .execute()
    }
    return page
  }

  /// Creates a link post — anything with no player of its own. The scraped
  /// headline goes in the page's title (the same column a YouTube title lands
  /// in) and the link itself in media_url as `media_type: "article"`.
  ///
  /// `meta` is whatever compose already scraped, so posting doesn't re-fetch
  /// the page: the author approved a specific preview and that's what ships.
  /// Nil metadata is a normal post — the card names the link by its host.
  ///
  /// The og:image is re-hosted best-effort. Unlike a photo post, where the image
  /// IS the post, a link stands up fine without one, so a failed re-host leaves
  /// poster_url nil instead of failing the submission.
  @discardableResult
  func createLinkPost(issueId: UUID, circleId: UUID, authorId: UUID, url: URL,
                      meta: OpenGraph.Meta?, caption: String?,
                      ) async throws -> Page {
    let page: Page = try await supabase.from("pages")
      .insert(PageInsert(issueId: issueId, submittedBy: authorId,
                         title: meta?.title ?? meta?.siteName,
                         caption: caption, captionStyle: .newsprintKicker))
      .select().single().execute().value

    var imagePath: String?
    if let image = meta?.imageURL {
      // Named for the page, not the link: two members sharing the same article
      // each get their own copy rather than racing to overwrite one file.
      imagePath = try? await rehostImage(from: image, circleId: circleId,
                                         named: page.id.uuidString.lowercased())
    }
    try await supabase.from("page_media")
      .insert(PageMediaInsert(pageId: page.id, mediaUrl: url.absoluteString,
                              mediaType: "article", posterUrl: imagePath, position: 0))
      .execute()

    if let caption {
      _ = try? await supabase.from("comments")
        .insert(CommentInsert(pageId: page.id, userId: authorId, body: caption))
        .execute()
    }
    return page
  }

  // MARK: Reactions

  /// Where a reaction photo lives, relative to the circle's folder. Deterministic
  /// on purpose: reacting again overwrites the same object instead of leaving the
  /// old one behind, so there's nothing to clean up.
  ///
  /// Lowercased, both ids. Swift's `uuidString` is uppercase and Postgres renders
  /// `uuid::text` lowercase — the same mismatch that made the storage policy deny
  /// everything once already (see `mediaPath`).
  nonisolated static func reactionName(pageId: UUID, userId: UUID) -> String {
    "reactions/\(pageId.uuidString.lowercased())-\(userId.uuidString.lowercased()).jpg"
  }

  /// React to a page with a photo, replacing your previous reaction if you had
  /// one — the DB's UNIQUE(page_id, user_id) makes "one per person" a fact rather
  /// than something the client has to remember.
  ///
  /// Upload first, like `createPhotoPost`: a storage failure then means no row at
  /// all, rather than a row pointing at a photo that isn't there.
  @discardableResult
  func upsertReaction(pageId: UUID, circleId: UUID, userId: UUID, jpeg: Data) async throws -> Reaction {
    let path = try await upload(jpeg, circleId: circleId,
                                name: Self.reactionName(pageId: pageId, userId: userId))
    return try await supabase.from("reactions")
      .upsert(ReactionInsert(pageId: pageId, userId: userId, mediaPath: path),
              onConflict: "page_id,user_id")
      .select().single().execute().value
  }

  /// Take your reaction back. The stored photo is left behind — it's in a private
  /// bucket only this circle can read, and reacting again reclaims it. Deleting it
  /// would need a storage DELETE policy, and the obvious version of that policy
  /// would also let anyone delete anyone else's post photo.
  func deleteReaction(pageId: UUID, userId: UUID) async throws {
    try await supabase.from("reactions")
      .delete()
      .eq("page_id", value: pageId.uuidString)
      .eq("user_id", value: userId.uuidString)
      .execute()
  }

  /// A page's comments, oldest first, each paired with its author (one extra
  /// round trip for the distinct authors, joined in memory).
  func fetchComments(pageId: UUID) async throws -> [CommentWithAuthor] {
    let comments: [Comment] = try await supabase.from("comments")
      .select().eq("page_id", value: pageId.uuidString)
      .order("created_at", ascending: true).execute().value
    guard !comments.isEmpty else { return [] }

    let authorIds = Array(Set(comments.map(\.userId.uuidString)))
    let authors: [User] = try await supabase.from("users")
      .select().in("id", values: authorIds).execute().value
    let byId = Dictionary(uniqueKeysWithValues: authors.map { ($0.id, $0) })
    return comments.map { CommentWithAuthor(comment: $0, author: byId[$0.userId]) }
  }

  func postComment(pageId: UUID, userId: UUID, body: String) async throws -> Comment {
    try await supabase.from("comments")
      .insert(CommentInsert(pageId: pageId, userId: userId, body: body))
      .select().single().execute().value
  }

  /// Delete a page (post). page_media and comments cascade; RLS limits this to
  /// the page's own author.
  func deletePage(pageId: UUID) async throws {
    try await supabase.from("pages").delete().eq("id", value: pageId.uuidString).execute()
  }

    func createCircle(name: String, creatorID: UUID) async throws -> Circle {

        let circle: Circle = try await supabase.from("circles")
            .insert(CircleInsert(name: name, createdBy: creatorID))
            .select().single().execute().value

        // insert first member
        try await supabase.from("circle_members")
            .insert(CircleMember(circleId: circle.id, userId: creatorID, joinedAt: Date()))
            .execute()

        return circle
    }

    /// Who has put something into the edition being assembled, and when.
    ///
    /// Deliberately returns no content — during the compose phase members see
    /// THAT others contributed, not what. RLS enforces that (`page_media` stays
    /// unreadable until the issue publishes); selecting only these two columns
    /// means this can't leak by accident either.
    ///
    /// Empty when no draft is open — nobody has submitted this week yet.
    func draftSubmissions(circleId: UUID) async throws -> [Submission] {
        guard let issueId = try await draftIssueId(circleId: circleId) else { return [] }
        struct Row: Decodable {
            let submittedBy: UUID?
            let createdAt: Date?
            enum CodingKeys: String, CodingKey {
                case submittedBy = "submitted_by"
                case createdAt = "created_at"
            }
        }
        let rows: [Row] = try await supabase.from("pages")
            .select("submitted_by, created_at").eq("issue_id", value: issueId.uuidString)
            .order("created_at", ascending: true).execute().value
        return rows.compactMap { row in
            row.submittedBy.map { Submission(authorId: $0, at: row.createdAt ?? .now) }
        }
    }

    /// The subset of `memberIds` who have contributed to the edition being
    /// assembled — the roster's "who's in this week".
    ///
    /// The DRAFT, not the live issue: under derived liveness there's always a
    /// live edition after week one, so asking about that one would show last
    /// week's contributors forever and never this week's.
    func submitterIds(among memberIds: [UUID], circleId: UUID) async throws -> Set<UUID> {
        let members = Set(memberIds)
        return Set(try await draftSubmissions(circleId: circleId)
            .map(\.authorId).filter(members.contains))
    }

    /// Joins the circle behind an invite code and returns it with its full
    /// member list, ready for the bubble field. Joining a circle you're
    /// already in is a no-op success.
    func joinCircle(code: String, userId: UUID) async throws -> CircleSummary {
        let circles: [Circle] = try await supabase.from("circles")
            .select().eq("invite_code", value: code.uppercased()).limit(1).execute().value
        guard let circle = circles.first else { throw JoinError.badCode }

        try await supabase.from("circle_members")
            .upsert(CircleMember(circleId: circle.id, userId: userId, joinedAt: Date()),
                    ignoreDuplicates: true)
            .execute()

        let members: [CircleMember] = try await supabase.from("circle_members")
            .select().eq("circle_id", value: circle.id.uuidString).execute().value
        let users: [User] = try await supabase.from("users")
            .select().in("id", values: members.map(\.userId.uuidString)).execute().value
        return CircleSummary(circle: circle, members: users)
    }
}

/// Keyless lookup of a YouTube video's public title via the official oEmbed
/// endpoint (no API key, no quota). Used at post-creation to cache the title.
enum YouTubeOEmbed {
  private struct Response: Decodable { let title: String }

  /// Test seam: unit tests swap in a URLProtocol-stubbed session.
  nonisolated(unsafe) static var session: URLSession = .shared

  enum Lookup {
    case found(title: String)
    case unavailable   // 4xx: private, removed, or bogus id — the video won't play either
    case unknown       // network hiccup or odd response — can't tell, don't block
  }

  static func lookup(forVideoID id: String) async -> Lookup {
    guard var components = URLComponents(string: "https://www.youtube.com/oembed") else { return .unknown }
    components.queryItems = [
      URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"),
      URLQueryItem(name: "format", value: "json"),
    ]
    guard let url = components.url else { return .unknown }
    do {
      // Short timeout: the default 60s leaves compose sitting on "Fetching
      // details…"; a missing title is fine, the post works without it.
      var request = URLRequest(url: url)
      request.timeoutInterval = 8
      let (data, response) = try await session.data(for: request)
      guard let status = (response as? HTTPURLResponse)?.statusCode else { return .unknown }
      oembedLog.info("oEmbed status \(status) for \(id, privacy: .public)")
      if (400..<500).contains(status) { return .unavailable }
      guard status == 200, let decoded = try? JSONDecoder().decode(Response.self, from: data)
      else { return .unknown }
      return .found(title: decoded.title)
    } catch {
      oembedLog.info("oEmbed error for \(id, privacy: .public): \(error, privacy: .public)")
      return .unknown
    }
  }

  /// The video's title, or nil if unavailable or the request fails.
  static func title(forVideoID id: String) async -> String? {
    if case .found(let title) = await lookup(forVideoID: id) { return title }
    return nil
  }
}

/// Instagram won't play inline and its official oEmbed now needs a token, so we
/// read the two things we can display from the public embed page: the reel's
/// cover-frame URL and the creator's @handle. Best-effort — a nil means we post
/// (or preview) without a real frame rather than blocking.
enum InstagramEmbed {
  struct Meta: Sendable { let posterURL: URL; let handle: String }

  /// Test seam: unit tests swap in a URLProtocol-stubbed session.
  nonisolated(unsafe) static var session: URLSession = .shared

  static func fetch(id: String, kind: InstagramContentType) async -> Meta? {
    let seg = kind == .post ? "p" : "reel"
    guard let url = URL(string: "https://www.instagram.com/\(seg)/\(id)/embed/captioned/") else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 8
    // The embed page only serves the poster markup to a browser-ish UA.
    request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await session.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let html = String(data: data, encoding: .utf8),
          let poster = parsePosterURL(html) else { return nil }
    return Meta(posterURL: poster, handle: parseHandle(html) ?? "")
  }

  /// src of `<img class="EmbeddedMediaImage" … src="…">` — the cover frame (not
  /// the profile pic, which is a separate <img> without that class).
  static func parsePosterURL(_ html: String) -> URL? {
    guard let anchor = html.range(of: "EmbeddedMediaImage"),
          let srcOpen = html.range(of: "src=\"", range: anchor.upperBound..<html.endIndex),
          let srcClose = html.range(of: "\"", range: srcOpen.upperBound..<html.endIndex) else { return nil }
    let raw = html[srcOpen.upperBound..<srcClose.lowerBound]
      .replacingOccurrences(of: "&amp;", with: "&")
    return URL(string: raw)
  }

  /// The handle inside `class="UsernameText">infinite_mantra</span>`.
  static func parseHandle(_ html: String) -> String? {
    guard let anchor = html.range(of: "UsernameText\">"),
          let close = html.range(of: "<", range: anchor.upperBound..<html.endIndex) else { return nil }
    let name = String(html[anchor.upperBound..<close.lowerBound])
    return name.isEmpty ? nil : name
  }
}

private enum Config {
  private static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

  static let supabaseURL: URL = {
    if isPreview { return URL(string: "https://preview.invalid")! }
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
          let url = URL(string: raw) else {
      fatalError("SUPABASE_URL missing from Info.plist — ensure Config.xcconfig is set in Xcode project configurations")
    }
    return url
  }()

  static let supabaseAnonKey: String = {
    if isPreview { return "preview-key" }
    guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else {
      fatalError("SUPABASE_ANON_KEY missing from Info.plist — ensure Config.xcconfig is set in Xcode project configurations")
    }
    return key
  }()
}
