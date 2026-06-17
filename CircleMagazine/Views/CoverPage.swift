//
//  CoverPage.swift
//  CircleMagazine
//
//  Full-bleed cover image with the "Circle" masthead, Thrasher-style.
//

import SwiftUI

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
                .font(.system(size: 60, weight: .black, design: .rounded))
                .kerning(2)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 10)
                .padding(.top, 20)
        }
        .frame(width: width, height: height)
        .clipped()
    }
}
