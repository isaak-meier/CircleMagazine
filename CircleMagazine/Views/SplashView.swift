//
//  SplashView.swift
//  CircleMagazine
//

import SwiftUI

/// Wraps the auth screen with the welcome splash. The splash sits on top and is
/// "cleared" by the ripple reveal, exposing AuthView beneath.
struct WelcomeView: View {
    let account: AccountManager
    @State private var revealed = false

    var body: some View {
        ZStack {
            AuthView(account: account)
            if !revealed {
                SplashView { revealed = true }
            }
        }
    }
}

struct SplashView: View {
    var onReveal: () -> Void

    @State private var showHint = false
    @State private var tap: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height) * 0.55

            ZStack {
                Color.white.ignoresSafeArea()

                ZStack {
                    SwiftUI.Circle().fill(.black).frame(width: d, height: d)
                    ArcText("Welcome to Circle", radius: d / 2 + 22, perChar: .degrees(9))
                        .font(Style.cardTitle)
                }

                VStack {
                    Spacer()
                    Text("tap anywhere to get started")
                        .foregroundStyle(.secondary)
                        .opacity(showHint ? 1 : 0)
                        .padding(.bottom, 40)
                }
            }
            .contentShape(Rectangle())
            .rippleReveal(origin: tap, onFinished: onReveal)
            .onTapGesture(coordinateSpace: .local) { location in
                if tap == nil { tap = location }
            }
        }
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeIn(duration: 0.6)) { showHint = true }
        }
    }
}

/// Text laid out along the top arc of a circle of the given radius.
private struct ArcText: View {
    let text: String
    let radius: CGFloat
    let perChar: Angle

    init(_ text: String, radius: CGFloat, perChar: Angle) {
        self.text = text
        self.radius = radius
        self.perChar = perChar
    }

    var body: some View {
        let chars = Array(text.enumerated())
        let mid = Double(text.count - 1) / 2
        ZStack {
            ForEach(chars, id: \.offset) { idx, ch in
                Text(String(ch))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .rotationEffect(perChar * (Double(idx) - mid))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

// Note: the ripple is a Metal shader and won't render in the canvas — run on a
// simulator/device to see the tap distortion.
