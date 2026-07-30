//
//  OpenGraph.swift
//  CircleMagazine
//
//  Link preview metadata for an arbitrary URL, read from the page's Open Graph
//  tags. YouTube has oEmbed and Instagram has its embed page; everything else
//  has to be scraped from whatever the site chose to publish.
//
//  Best-effort by design: a nil means the card falls back to showing the bare
//  link rather than the post being blocked. Most of the web is missing, lying
//  about, or JavaScript-rendering its metadata, and none of that is a reason a
//  member can't share something.
//
//  Lives outside DatabaseService because it talks to the open web, not Supabase.
//

import Foundation

enum OpenGraph {
    /// What we could read. Never handed back empty — `fetch` returns nil rather
    /// than a Meta with nothing in it, so "no preview" is one answer instead of
    /// three fields the caller has to check.
    /// `nonisolated` because the project defaults types to `@MainActor`, and a
    /// value this inert has no business being pinned to the UI thread.
    nonisolated struct Meta: Sendable, Equatable {
        let title: String?
        let imageURL: URL?
        let siteName: String?

        var isEmpty: Bool { title == nil && imageURL == nil && siteName == nil }
    }

    /// Test seam: unit tests swap in a URLProtocol-stubbed session.
    nonisolated(unsafe) static var session: URLSession = .shared

    /// Stop reading after this much of the page. Open Graph tags live in
    /// `<head>`, so anything past here is body we'd throw away — and this is a
    /// URL a member pasted, pointed at a host we know nothing about, so the
    /// response size can't be left to the far end to decide.
    private static let maxBytes = 256 * 1024

    static func fetch(_ url: URL) async -> Meta? {
        // https only: the reader's request goes to whatever host was pasted, so
        // it shouldn't also go in the clear.
        guard url.scheme == "https" else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        // Plenty of sites serve metadata-free markup to anything that doesn't
        // look like a browser — same trick the Instagram embed needs.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }

        // Streamed rather than `data(for:)` so the cap holds even when the
        // server declares a small body and then sends a large one.
        var data = Data()
        data.reserveCapacity(min(maxBytes, 64 * 1024))
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maxBytes { break }
            }
        } catch {
            // A truncated read still parses — a page that died mid-body may
            // already have given us the whole head.
            guard !data.isEmpty else { return nil }
        }

        // Most of the web is UTF-8; latin1 never fails, so a mislabelled page
        // degrades to slightly wrong accents rather than no preview at all.
        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        else { return nil }

        // The *final* URL, so a relative og:image resolves against wherever the
        // redirects actually landed.
        return parse(html, relativeTo: http.url ?? url)
    }

    // MARK: Parsing

    /// Reads `<meta>` tags plus `<title>`. Nil when the page gave us nothing.
    ///
    /// Parsing is pure string work, so it and its helpers stay off the main
    /// actor — the project defaults types to `@MainActor`, which would otherwise
    /// drag a scrape of a 256 KB page onto the UI thread.
    nonisolated static func parse(_ html: String, relativeTo base: URL) -> Meta? {
        let tags = metaTags(in: html)

        // og:* first, then twitter:* — a lot of sites publish only the latter.
        let title = tags["og:title"] ?? tags["twitter:title"] ?? titleTag(html)
        let image = tags["og:image"] ?? tags["og:image:url"] ?? tags["twitter:image"]
        let site  = tags["og:site_name"] ?? tags["application-name"]

        let meta = Meta(title: title.map(decode),
                        imageURL: image.flatMap { URL(string: decode($0), relativeTo: base)?.absoluteURL },
                        siteName: site.map(decode))
        return meta.isEmpty ? nil : meta
    }

    /// Every `<meta>` in the document as property → content.
    ///
    /// Attribute order isn't fixed and the key lives under `property` on Open
    /// Graph but `name` on Twitter's, so both are read and whichever appears
    /// first in the tag wins. First occurrence of a key wins overall, matching
    /// how scrapers generally treat duplicate tags.
    nonisolated private static func metaTags(in html: String) -> [String: String] {
        var found: [String: String] = [:]
        for tag in matches(of: #"<meta\b[^>]*>"#, in: html) {
            guard let key = attribute("property", in: tag) ?? attribute("name", in: tag),
                  key.hasPrefix("og:") || key.hasPrefix("twitter:") || key == "application-name",
                  let content = attribute("content", in: tag), !content.isEmpty,
                  found[key] == nil
            else { continue }
            found[key] = content
        }
        return found
    }

    /// `<title>…</title>`, the last resort when a page publishes no cards at all.
    nonisolated private static func titleTag(_ html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let gt = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title", options: .caseInsensitive,
                                     range: gt.upperBound..<html.endIndex)
        else { return nil }
        let text = html[gt.upperBound..<close.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The value of `name="…"` / `name='…'` inside a single tag.
    nonisolated private static func attribute(_ name: String, in tag: String) -> String? {
        for quote in ["\"", "'"] {
            let pattern = "\(name)\\s*=\\s*\(quote)([^\(quote)]*)\(quote)"
            if let value = matches(of: pattern, in: tag, group: 1).first { return value }
        }
        return nil
    }

    nonisolated private static func matches(of pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return [] }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: full).compactMap { match in
            guard let range = Range(match.range(at: group), in: text) else { return nil }
            return String(text[range])
        }
    }

    /// The handful of entities that actually show up in title and image
    /// attributes. Not a general HTML decoder, and doesn't need to be.
    nonisolated private static func decode(_ raw: String) -> String {
        var s = raw
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"),
                               ("&#x27;", "'"), ("&apos;", "'"), ("&lt;", "<"),
                               ("&gt;", ">"), ("&nbsp;", " ")] {
            s = s.replacingOccurrences(of: entity, with: char, options: .caseInsensitive)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
