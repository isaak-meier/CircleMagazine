//
//  EditorialStyles.swift
//  CircleMagazine
//
//  Shared control styling so screens match: a full-width ink "pill" button, a
//  quiet text-link button, and a paper text-field look.
//

import SwiftUI

/// Full-width ink pill — the app's primary action. When `loading`, the label is
/// replaced by a spinner in place (button keeps its size).
struct PrimaryButtonStyle: ButtonStyle {
    var loading = false

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label
                .font(Style.button)
                .foregroundStyle(Style.paper)
                .opacity(loading ? 0 : 1)
            if loading { ProgressView().tint(Style.paper) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Style.Space.md)
        .background(RoundedRectangle(cornerRadius: Style.mediaRadius).fill(Style.ink))
        .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Quiet secondary action (e.g. "Resend").
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Style.link)
            .foregroundStyle(Style.meta)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { .init() }
    static func primary(loading: Bool) -> PrimaryButtonStyle { .init(loading: loading) }
}
extension ButtonStyle where Self == LinkButtonStyle {
    static var link: LinkButtonStyle { .init() }
}

extension View {
    /// Paper field with a hairline rule — matches the editorial palette.
    func editorialField() -> some View {
        self
            .font(Style.field).foregroundStyle(Style.ink)
            .padding(Style.Space.md)
            .background(RoundedRectangle(cornerRadius: Style.mediaRadius).fill(Style.paper))
            .overlay(RoundedRectangle(cornerRadius: Style.mediaRadius).stroke(Style.rule, lineWidth: 1))
    }
}
