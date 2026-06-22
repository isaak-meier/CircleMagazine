//
//  CoverPage.swift
//  CircleMagazine
//
//  Full-bleed cover image with the "Circle" masthead, Thrasher-style.
//

import SwiftUI
import UIKit

struct CoverPage: View {
    let imageURL: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
            } else {
                Color.black
            }

            Text("CIRCLE")
            .font(.system(size: 60, weight: .black, design: .serif))
                .kerning(2)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 10)
                .padding(.top, topSafeInset + 30)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    // Parent ignoresSafeArea, so a child GeometryReader reports 0 insets —
    // read the key window's top inset directly to clear the notch.
    private var topSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }
}
