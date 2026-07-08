//
//  Masthead.swift
//  CircleMagazine
//
//  The editorial screen header: a serif wordmark over a 2pt ink rule. The feed
//  passes an edition date for the right-side stamp; Circles passes its count;
//  other screens omit it.
//

import SwiftUI

struct Masthead: View {
    let title: String
    var stamp: String? = nil
    var eyebrow: String = "THIS SUNDAY'S EDITION"

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(Style.wordmark).foregroundStyle(Style.ink)
            Spacer()
            if let stamp {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(eyebrow)
                        .font(Style.eyebrow).tracking(1.6)
                    Text(stamp)
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
