//
//  RippleReveal.swift
//  CircleMagazine
//
//  The app's signature transition, extracted from the splash screen: the
//  Ripple Metal shader radiates from a tap point while a circular hole grows
//  from it, revealing whatever sits beneath in the ZStack. Attach with
//  `.rippleReveal(origin:onFinished:)` — inert while `origin` is nil.
//

import SwiftUI

extension View {
    func rippleReveal(origin: CGPoint?, duration: TimeInterval = 1.2,
                      onFinished: @escaping () -> Void) -> some View {
        modifier(RippleRevealModifier(origin: origin, duration: duration, onFinished: onFinished))
    }
}

struct RippleRevealModifier: ViewModifier {
    var origin: CGPoint?
    var duration: TimeInterval
    var onFinished: () -> Void

    @State private var holeRadius: CGFloat = 0
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: origin) { view, elapsedTime in
                view.modifier(RippleModifier(origin: origin, elapsedTime: elapsedTime,
                                             duration: duration))
            } keyframes: { _ in
                LinearKeyframe(duration, duration: duration)
            }
            // With no reveal in flight the radius is 0, so this is a full-
            // coverage mask (no hole) — one stable branch, no identity swap
            // that would reset the content's state mid-transition.
            .mask {
                HoleShape(center: origin ?? .zero, radius: holeRadius)
                    .fill(style: FillStyle(eoFill: true))
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onChange(of: origin) { _, tapped in
                guard let tapped else { holeRadius = 0; return }  // reset for the next reveal
                withAnimation(.easeIn(duration: duration * 0.75)) {
                    holeRadius = maxRadius(from: tapped)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { onFinished() }
            }
    }

    /// Far enough to swallow the whole view from any tap point — padded so the
    /// hole also covers background bled into the safe areas.
    private func maxRadius(from p: CGPoint) -> CGFloat {
        hypot(max(p.x, size.width - p.x), max(p.y, size.height - p.y)) + 100
    }
}

/// Plays the `Ripple` Metal shader as a `layerEffect` radiating from `origin`.
/// `elapsedTime` is animated 0…duration to drive the wave; inert until a tap sets
/// an origin, so it doesn't fire on first appearance.
struct RippleModifier: ViewModifier {
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

/// A full-rect path with a circular hole punched out (even-odd fill) — used as a
/// mask to reveal what's beneath as the radius grows.
struct HoleShape: Shape {
    var center: CGPoint
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // The outer rect overshoots the bounds so the mask keeps showing
        // backgrounds that bleed into the safe areas (status bar, home
        // indicator) — clipping them left bare strips top and bottom.
        var p = Path(rect.insetBy(dx: -1000, dy: -1000))
        p.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2))
        return p
    }
}
