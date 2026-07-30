//
//  Avatar.swift
//  CircleMagazine
//
//  One member, one circle. Shows their picture when they have one and their
//  initials when they don't — which is every member today, since nothing in the
//  app writes `avatar_url` yet. The day something does, every screen using this
//  starts showing faces at once.
//
//  Written because four screens each had their own copy: only the card's author
//  row bothered with `avatar_url`, and the two that coloured the circle keyed the
//  colour off a member's position in an array — so the same person was a
//  different colour on the chat screen than on the members sheet.
//

import SwiftUI

struct Avatar: View {
    let user: User
    var diameter: CGFloat = 30
    /// A ring in the surface colour, so overlapping avatars in a cluster stay
    /// legible against each other. Nil for a standalone avatar.
    var ring: Color? = nil

    var body: some View {
        monogram
            .overlay {
                // The picture sits on top of the initials rather than replacing
                // them, so there's no flash of empty circle while it loads and
                // no layout change if it never arrives.
                if let url = user.avatarUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() }
                        placeholder: { Color.clear }
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(SwiftUI.Circle())
            .overlay {
                if let ring {
                    SwiftUI.Circle().stroke(ring, lineWidth: 2)
                }
            }
    }

    private var monogram: some View {
        Self.color(for: user)
            .overlay {
                Text(user.initials)
                    // Scales with the circle, so one component serves a 22pt
                    // cluster face and a 32pt author row.
                    .font(.system(size: diameter * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    /// Keyed off the user's id, not their position in any list — a card has no
    /// members array to index into, and position-based colour means the same
    /// person changes colour between screens.
    ///
    /// Summing the uuid's own bytes rather than `hashValue`: Swift seeds its
    /// hasher per process, so `hashValue` gave each person a *new* colour on
    /// every launch.
    static func color(for user: User) -> Color {
        let palette = Style.avatarColors
        let sum = withUnsafeBytes(of: user.id.uuid) { $0.reduce(0) { $0 + Int($1) } }
        return palette[sum % palette.count]
    }
}

#if DEBUG
#Preview("Avatar") {
    let dave = User(id: UUID(), username: "Dave Slater", bio: nil, avatarUrl: nil, role: nil,
                    followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    let jm = User(id: UUID(), username: "jmoney", bio: nil, avatarUrl: nil, role: nil,
                  followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    return HStack(spacing: Style.Space.lg) {
        Avatar(user: dave, diameter: 22)
        Avatar(user: dave)
        Avatar(user: jm, diameter: 44)
        HStack(spacing: -10) {   // the cluster treatment
            Avatar(user: dave, diameter: 26, ring: Style.paper)
            Avatar(user: jm, diameter: 26, ring: Style.paper)
        }
    }
    .padding()
    .background(Style.paper)
}
#endif
