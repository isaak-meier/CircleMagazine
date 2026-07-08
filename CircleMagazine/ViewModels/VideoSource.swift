//
//  VideoSource.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/30/26.
//

import Foundation

enum VideoSource {
    case youtube(id: String)
    case insta(id: String, kind: InstagramContentType)
    // instagram has different content types we need to detect, so store that info for when we reconstruct the url
    case rawFile(URL)

    init?(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = components?.host ?? ""

        if host.contains("youtu.be") {
                // Short share link: the id is the path, e.g. youtu.be/aB3xK9q
            guard let id = url.pathComponents.last, url.pathComponents.count > 1, !id.isEmpty
            else { return nil }
            self = .youtube(id: id)
        } else if host.contains("youtube.com") {
                // Shorts link: youtube.com/shorts/<id>. The /embed/ iframe plays
                // Shorts fine, so no separate case needed.
            if let i = url.pathComponents.firstIndex(of: "shorts"),
               url.pathComponents.indices.contains(i + 1) {
                self = .youtube(id: url.pathComponents[i + 1])
            } else if let id = components?.queryItems?.first(where: { $0.name == "v" })?.value,
                      !id.isEmpty {
                // Watch link — id is in ?v=… ; no id ⇒ bogus link, reject.
                self = .youtube(id: id)
            } else { return nil }
        } else if host.contains("instagram.com") {
            // firstIndex(where: ...) is fancy! skips for in range
            guard let index = url.pathComponents.firstIndex(where: { InstagramContentType(rawValue: $0) != nil }),
                  let kind = InstagramContentType(rawValue: url.pathComponents[index]),
                    url.pathComponents.indices.contains(index + 1) else { return nil }
            let id = url.pathComponents[index + 1]
            self = .insta(id: id, kind: kind)
        } else {
                // Any other valid URL: treat as a directly playable file.
            self = .rawFile(url)
        }
    }
}

enum InstagramContentType: String {
    case post = "p"
    case reel = "reel"
    case reels = "reels"
}
