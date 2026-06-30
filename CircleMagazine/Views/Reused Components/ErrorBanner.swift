//
//  ErrorBanner.swift
//  CircleMagazine
//
//  A small inline error banner — warning glyph + message on a tinted rounded
//  field. Reusable anywhere a recoverable failure needs surfacing (compose,
//  feed load failures, auth, …).
//

import SwiftUI

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 13).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.red.opacity(0.25), lineWidth: 1))
    }
}

#Preview {
    ErrorBanner(message: "Couldn't post your video — the network connection was lost.")
        .padding()
        .background(Style.paper)
}
