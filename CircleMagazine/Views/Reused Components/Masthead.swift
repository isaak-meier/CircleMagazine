//
//  Masthead.swift
//  CircleMagazine
//
//  The editorial screen header: a serif wordmark over a 2pt ink rule. The feed
//  passes an edition date for the right-side stamp; other screens omit it.
//

import SwiftUI

struct Masthead: View {
    let title: String
    var editionDate: String? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(Style.wordmark).foregroundStyle(Style.ink)
            Spacer()
            if let editionDate {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("THIS SUNDAY'S EDITION")
                        .font(Style.eyebrow).tracking(1.6)
                    Text(editionDate)
                        .font(Style.stamp).tracking(0.6)
                }
                .foregroundStyle(Style.edition)
            }
        }
        .padding(.bottom, Style.Space.md)
        .overlay(alignment: .bottom) { Rectangle().fill(Style.ink).frame(height: 2) }
        .padding(.horizontal, Style.Space.lg)
        .padding(.top, Style.Space.sm)
    }
}
