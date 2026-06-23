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
    @State private var holeRadius: CGFloat = 0

    private let rippleDuration: TimeInterval = 1.2

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
            .keyframeAnimator(initialValue: 0.0, trigger: tap) { view, elapsedTime in
                view.modifier(RippleModifier(origin: tap, elapsedTime: elapsedTime, duration: rippleDuration))
            } keyframes: { _ in
                LinearKeyframe(rippleDuration, duration: rippleDuration)
            }
            .contentShape(Rectangle())
            .mask {
                if let tap {
                    HoleShape(center: tap, radius: holeRadius).fill(style: FillStyle(eoFill: true))
                } else {
                    Rectangle()
                }
            }
            .onTapGesture(coordinateSpace: .local) { location in
                fire(at: location, in: geo.size)
            }
        }
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeIn(duration: 0.6)) { showHint = true }
        }
    }

    private func maxRadius(from p: CGPoint, in size: CGSize) -> CGFloat {
        hypot(max(p.x, size.width - p.x), max(p.y, size.height - p.y))
    }

    private func fire(at location: CGPoint, in size: CGSize) {
        guard tap == nil else { return }
        tap = location
        withAnimation(.easeIn(duration: 0.9)) { holeRadius = maxRadius(from: location, in: size) }
        DispatchQueue.main.asyncAfter(deadline: .now() + rippleDuration) { onReveal() }
    }
}

/// Plays the `Ripple` Metal shader as a `layerEffect` radiating from `origin`.
/// `elapsedTime` is animated 0…duration to drive the wave; inert until a tap sets
/// an origin, so it doesn't fire on first appearance.
private struct RippleModifier: ViewModifier {
    var origin: CGPoint?
    var elapsedTime: TimeInterval
    var duration: TimeInterval

    var amplitude: Double = 12
    var frequency: Double = 15
    var decay: Double = 8
    var speed: Double = 1200

    // Only attach the layerEffect once a tap is in flight. Attaching it at all
    // forces SwiftUI to compile the Metal pipeline — and on the Simulator that
    // compile takes seconds, which is what hung the app at launch.
    @ViewBuilder
    func body(content: Content) -> some View {
        if let o = origin, elapsedTime > 0, elapsedTime < duration {
            content.visualEffect { view, _ in
                view.layerEffect(
                    ShaderLibrary.Ripple(
                        .float2(o),
                        .float(Float(elapsedTime)),
                        .float(Float(amplitude)),
                        .float(Float(frequency)),
                        .float(Float(decay)),
                        .float(Float(speed))
                    ),
                    maxSampleOffset: CGSize(width: amplitude, height: amplitude)
                )
            }
        } else {
            content
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

/// A full-rect path with a circular hole punched out (even-odd fill) — used as a
/// mask to reveal what's beneath as the radius grows.
private struct HoleShape: Shape {
    var center: CGPoint
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2))
        return p
    }
}

// Note: the ripple is a Metal shader and won't render in the canvas — run on a
// simulator/device to see the tap distortion.
