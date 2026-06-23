//
//  Magazine.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/22/26.
//

import Foundation

struct Magazine {
    let issue: Issue
    let pages: [MagazinePage]

    // converts the magazine to viewModels, where each page maps to one card
    var cards: [CardViewModel] {
        pages.map { page in
            CardViewModel(from: page)
        }
    }
}

struct MagazinePage {
    let page: Page
    let widgets: [PageMedia]
}

extension Magazine {
        /// Sample issue for previews — a cover plus two mixed widget spreads.
    static let sample: Magazine = {
        let issueId = UUID()
        func page() -> Page { Page(id: UUID(), issueId: issueId, submittedBy: nil, createdAt: nil) }
        func media(_ type: String, url: String? = nil, text: String? = nil, _ pos: Int) -> PageMedia {
            PageMedia(id: UUID(), pageId: nil, mediaUrl: url, mediaType: type,
                      textContent: text, position: pos, createdAt: nil)
        }
        let cover = MagazinePage(page: page(), widgets: [
            media("image", url: "https://picsum.photos/seed/cover/800/1200", 0)
        ])
        let spread1 = MagazinePage(page: page(), widgets: [
            media("text", text: """
      You do not have to be good. You do not have to walk on your knees \
      for a hundred miles through the desert, repenting. You only have to let \
      the soft animal of your body love what it loves.
      """, 0),
            media("image", url: "https://picsum.photos/seed/a/600", 1),
            media("image", url: "https://picsum.photos/seed/b/600", 2),
            media("text", text: "On slowness, and the things we miss when we rush.", 3),
        ])
        let spread2 = MagazinePage(page: page(), widgets: [
            media("text", text: """
      ⊹˚₊  𝐀𝐅𝐅𝚰𝐑𝐌𝐀𝐓𝚰𝐎𝐍𝐒  ₊˚⊹
      
      I trust divine timing with calm certainty.
      Everything is syncing perfectly in my favor.
      I am guided into the right connections and the right outcomes.
      What is meant for me cannot miss me.
      I release impatience and welcome peace.
      My path is being arranged with protection and care.
      I choose balance, clarity, and steady progress.
      I am exactly where I need to be right now.
      Support arrives at the perfect time, in the perfect way for me.
      Everything is quietly falling into place.
      Everything aligns in my favor — starting now (𝟐𝟐𝟐) ✨
      """, 0),
            media("audio", url: "https://example.com/clip.mp3", 1),
            media("image", url: "https://picsum.photos/seed/c/600", 2),
            media("text", text: "Field notes from a long walk.", 3),
        ])
        return Magazine(
            issue: Issue(id: issueId, publishDate: "2026-06-22", isLive: true, createdAt: nil),
            pages: [cover, spread1, spread2]
        )
    }()
}
