//
//  CirclesView.swift
//  CircleMagazine
//
//  The Circles tab (from the Circles.dc.html mockup): the user's circles as a
//  floating bubble collage — bigger circle, more members — over the editorial
//  masthead. Tapping a bubble opens a bottom sheet with the member roster and
//  an Enter action.
//

import SwiftUI

/// A circle the signed-in user belongs to, with members loaded for the bubble
/// size and the sheet's avatar row.
struct CircleSummary: Identifiable {
    let circle: Circle
    let members: [User]
    var id: UUID { circle.id }
    var name: String { circle.name ?? "Untitled" }
}

// MARK: - Bubble collage layout

/// The mockup's hand-placed collage, kept as fixed slots (position, diameter,
/// tone) ordered biggest-first. Circles ranked by member count take slots in
/// order, so relative size always reads as relative aliveness.
/// ponytail: rank-based fixed slots, not a packing algorithm — add one only if
/// real member counts must drive exact bubble sizes.
enum CircleBubbleLayout {
    struct Slot {
        let x: CGFloat, y: CGFloat, diameter: CGFloat
        let tone: BubbleTone
    }

    struct BubbleTone {
        let hi: Color, lo: Color, fg: Color
    }

    /// The mockup was drawn on a 390pt-wide, 600pt-tall field; positions scale
    /// from there to the actual width.
    static let designWidth: CGFloat = 390
    static let cycleHeight: CGFloat = 600

    static let slots: [Slot] = [
        Slot(x: 44, y: 168, diameter: 208,
             tone: .init(hi: Color(hex: 0x2E2E48), lo: Color(hex: 0x16162A), fg: Color(hex: 0xF4F2EE))),
        Slot(x: 196, y: 96, diameter: 120,
             tone: .init(hi: Color(hex: 0xC97A5C), lo: Color(hex: 0xA24C34), fg: Color(hex: 0xFBF1EC))),
        Slot(x: 168, y: 388, diameter: 116,
             tone: .init(hi: Color(hex: 0x34506A), lo: Color(hex: 0x1D3346), fg: Color(hex: 0xF0F4F6))),
        Slot(x: 248, y: 300, diameter: 100,
             tone: .init(hi: Color(hex: 0x56687A), lo: Color(hex: 0x3A4A5A), fg: Color(hex: 0xF1F4F6))),
        Slot(x: 26, y: 44, diameter: 92,
             tone: .init(hi: Color(hex: 0x7E8C6A), lo: Color(hex: 0x5C6A48), fg: Color(hex: 0xF6F7F0))),
        Slot(x: 36, y: 434, diameter: 78,
             tone: .init(hi: Color(hex: 0xB5654A), lo: Color(hex: 0x8A4230), fg: Color(hex: 0xFBF1EC))),
        Slot(x: 40, y: 150, diameter: 66,
             tone: .init(hi: Color(hex: 0xE3D6C1), lo: Color(hex: 0xCBB99C), fg: Color(hex: 0x4A3E2C))),
    ]

    /// Slot for the i-th ranked circle — cycles the collage, pushing each full
    /// cycle down by one field height so any count fits.
    static func slot(_ i: Int) -> Slot {
        let base = slots[i % slots.count]
        let dy = CGFloat(i / slots.count) * cycleHeight
        return Slot(x: base.x, y: base.y + dy, diameter: base.diameter, tone: base.tone)
    }

    static func fieldHeight(count: Int) -> CGFloat {
        cycleHeight * CGFloat(max(1, (count + slots.count - 1) / slots.count))
    }
}

// MARK: - Bubble physics

/// Drives the bubbles' idle motion: slow constant drift with elastic
/// bubble/bubble and wall bounces, simulated in the mockup's 390pt design
/// space. Plain class on purpose — TimelineView redraws every frame and reads
/// fresh positions, so no observation is needed.
/// ponytail: O(n²) pair checks — fine below a few dozen bubbles.
final class BubblePhysics {
    struct Body {
        var pos: CGPoint
        var vel: CGVector
        let radius: CGFloat
        var mass: CGFloat { radius * radius }  // big bubbles barely budge
    }

    var bodies: [Body] = []
    private(set) var bounds: CGSize = .zero
    private var lastTick: Date?

    /// (Re)seed one body per circle at its collage slot, drifting in a random
    /// direction. No-op while the count is unchanged.
    func sync(count: Int) {
        guard bodies.count != count else { return }
        bounds = CGSize(width: CircleBubbleLayout.designWidth,
                        height: CircleBubbleLayout.fieldHeight(count: count))
        bodies = (0..<count).map { i in
            let slot = CircleBubbleLayout.slot(i)
            let r = slot.diameter / 2
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let speed = CGFloat.random(in: 8...16)
            return Body(pos: CGPoint(x: slot.x + r, y: slot.y + r),
                        vel: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                        radius: r)
        }
        lastTick = nil
    }

    /// Confine the field to the visible viewport (no scrolling) so bubbles
    /// bounce off the real screen edges. Called with the design-space height.
    func fit(designHeight h: CGFloat) {
        guard h > 0, bounds.height != h else { return }
        bounds.height = h
    }

    func tick(to now: Date) {
        // Clamp dt so returning from a pause doesn't teleport bubbles.
        let dt = min(now.timeIntervalSince(lastTick ?? now), 1.0 / 30.0)
        lastTick = now
        step(dt: CGFloat(dt))
    }

    func step(dt: CGFloat) {
        guard dt > 0 else { return }
        for i in bodies.indices {
            bodies[i].pos.x += bodies[i].vel.dx * dt
            bodies[i].pos.y += bodies[i].vel.dy * dt
        }
        for i in bodies.indices {
            for j in bodies.indices where j > i { collide(i, j) }
        }
        for i in bodies.indices { bounceOffWalls(i) }
    }

    /// Elastic circle/circle collision: push the pair out of overlap, then do
    /// the 1-D elastic swap of the velocity components along the contact
    /// normal (tangential parts unchanged), weighted by mass.
    private func collide(_ i: Int, _ j: Int) {
        var a = bodies[i], b = bodies[j]
        let dx = b.pos.x - a.pos.x, dy = b.pos.y - a.pos.y
        let minDist = a.radius + b.radius
        let distSq = dx * dx + dy * dy
        guard distSq < minDist * minDist else { return }
        let dist = max(sqrt(distSq), 0.001)
        let nx = dx / dist, ny = dy / dist

        let overlap = minDist - dist
        let total = a.mass + b.mass
        a.pos.x -= nx * overlap * (b.mass / total)
        a.pos.y -= ny * overlap * (b.mass / total)
        b.pos.x += nx * overlap * (a.mass / total)
        b.pos.y += ny * overlap * (a.mass / total)

        let van = a.vel.dx * nx + a.vel.dy * ny
        let vbn = b.vel.dx * nx + b.vel.dy * ny
        if van - vbn > 0 {  // only bounce if actually approaching
            let van2 = (van * (a.mass - b.mass) + 2 * b.mass * vbn) / total
            let vbn2 = (vbn * (b.mass - a.mass) + 2 * a.mass * van) / total
            a.vel.dx += (van2 - van) * nx; a.vel.dy += (van2 - van) * ny
            b.vel.dx += (vbn2 - vbn) * nx; b.vel.dy += (vbn2 - vbn) * ny
        }
        bodies[i] = a; bodies[j] = b
    }

    /// Slingshot release: the bubble was dragged by `pull` (design-space), so
    /// it sits at the stretched position — launch it the opposite way with force
    /// equal to the stretch, and it bounces around off the walls from there.
    /// ponytail: `launch` is the spring constant — bump it for a springier fling.
    func slingshot(_ index: Int, pull: CGVector, launch k: CGFloat = 6) {
        guard bodies.indices.contains(index) else { return }
        bodies[index].pos.x += pull.dx
        bodies[index].pos.y += pull.dy
        bodies[index].vel = CGVector(dx: -pull.dx * k, dy: -pull.dy * k)
    }

    private func bounceOffWalls(_ i: Int) {
        var b = bodies[i]
        if b.pos.x < b.radius { b.pos.x = b.radius; b.vel.dx = abs(b.vel.dx) }
        if b.pos.x > bounds.width - b.radius { b.pos.x = bounds.width - b.radius; b.vel.dx = -abs(b.vel.dx) }
        if b.pos.y < b.radius { b.pos.y = b.radius; b.vel.dy = abs(b.vel.dy) }
        if b.pos.y > bounds.height - b.radius { b.pos.y = bounds.height - b.radius; b.vel.dy = -abs(b.vel.dy) }
        bodies[i] = b
    }
}

// MARK: - Screen

enum ActiveSheet: Identifiable, Hashable {
    /// prefill: an invite code arriving via deep link, typed for the user.
    case join(prefill: String?)
    case create
    var id: Self { self }
}

struct CirclesView: View {
    let db: DatabaseService
    let account: AccountManager
    /// False while another tab is showing — pauses the bubble simulation.
    var active = true
    /// Bubble tapped: the circle, its tone, and the tap point in the
    /// "root" coordinate space — RootTabView ripples into the chat from there.
    let onEnter: (CircleSummary, CircleBubbleLayout.BubbleTone, CGPoint) -> Void

    /// An invite code arriving via deep link — consumed (reset to nil) once the
    /// join sheet opens with it.
    @Binding var joinCode: String?

    enum LoadState { case loading, loaded([CircleSummary]), failed(String) }
    @State private var state: LoadState
    @State private var sheetState: ActiveSheet?
    @State private var physics = BubblePhysics()

    init(db: DatabaseService, account: AccountManager, active: Bool = true,
         initial: LoadState = .loading, joinCode: Binding<String?> = .constant(nil),
         onEnter: @escaping (CircleSummary, CircleBubbleLayout.BubbleTone, CGPoint) -> Void) {
        self.db = db
        self.account = account
        self.active = active
        self.onEnter = onEnter
        _joinCode = joinCode
        _state = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            Masthead(title: "Circles")
                .overlay(alignment: .trailing) {
                    joinCreateMenu.padding(.trailing, Style.Space.lg)
                }
            switch state {
            case .loading:
                Spacer()
                ProgressView()
                Spacer()
            case .failed(let message):
                Spacer()
                Text(message).font(Style.body).foregroundStyle(Style.meta)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
                Spacer()
            case .loaded(let circles) where circles.isEmpty:
                emptyState
            case .loaded(let circles):
                bubbleField(circles)
            }
        }
        .background(Style.chrome)
        .task { await load() }
        .sheet(item: $sheetState) { sheet in
            switch sheet {
            case .create:
                CircleFormSheet(title: "Create a Circle", placeholder: "Name your circle",
                                cta: "Create", busyCta: "Creating…",
                                errorPrefix: "Couldn't create your circle", onSubmit: create)
            case .join(let prefill):
                CircleFormSheet(title: "Join a Circle", placeholder: "Invite code",
                                cta: "Join", busyCta: "Joining…",
                                errorPrefix: "Couldn't join", codeLength: 6,
                                initialInput: prefill ?? "", onSubmit: join)
            }
        }
        .onChange(of: joinCode) { _, code in
            guard let code else { return }
            sheetState = .join(prefill: code)
            joinCode = nil  // consume, so the same link can fire again later
        }
    }

    // MARK: Join / Create

    /// Sits in the masthead's top right — the same bare ink plus as the circle
    /// chat/members header. The empty state keeps its full-width pills too.
    private var joinCreateMenu: some View {
        Menu {
            Button("Join a Circle") { sheetState = .join(prefill: nil) }
            Button("Create a Circle") { sheetState = .create }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Style.ink)
                .frame(width: 30, height: 30, alignment: .trailing)
        }
    }

    // The mockup's empty state: floating pastel circles behind a centered
    // message and full-width Join/Create pills.
    private var emptyState: some View {
        ZStack {
            FloatingBackdrop()
            VStack(spacing: Style.Space.xl) {
                Text("You don't belong to any circles yet.")
                    .font(Style.field).foregroundStyle(Style.meta)
                    .multilineTextAlignment(.center)
                VStack(spacing: 14) {
                    CirclePillButton(title: "Join a Circle", filled: true, height: 58) {
                        sheetState = .join(prefill: nil)
                    }
                    CirclePillButton(title: "Create a Circle", filled: false, height: 58) {
                        sheetState = .create
                    }
                }
            }
            .padding(.horizontal, Style.Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }


    private func bubbleField(_ circles: [CircleSummary]) -> some View {
        let ranked = circles.sorted { $0.members.count > $1.members.count }
        physics.sync(count: ranked.count)
        return GeometryReader { geo in
            let scale = geo.size.width / CircleBubbleLayout.designWidth
            // No ScrollView: the bubbles bounce within the visible screen.
            let _ = physics.fit(designHeight: geo.size.height / scale)
            TimelineView(.animation(minimumInterval: nil, paused: !active)) { timeline in
                let _ = physics.tick(to: timeline.date)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { i, summary in
                        let slot = CircleBubbleLayout.slot(i)
                        CircleBubble(summary: summary, slot: slot, scale: scale,
                                     center: physics.bodies[i].pos,
                                     onTap: { tapPoint in onEnter(summary, slot.tone, tapPoint) },
                                     onLaunch: { pull in physics.slingshot(i, pull: pull) })
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
    }

    @MainActor
    private func load() async {
        guard case .loading = state else { return }  // preview injected data
        guard case .signedIn(let user) = account.authState else {
            state = .failed("Sign in to see your circles.")
            return
        }
        do {
            state = .loaded(try await db.fetchCircles(memberOf: user.id))
        } catch {
            state = .failed("Couldn't load your circles — \(error.localizedDescription)")
        }
    }

    /// Creates the circle and grows a new bubble for it in place. Throws so the
    /// sheet can show the failure and keep the typed name for a retry.
    @MainActor
    private func create(named name: String) async throws {
        guard case .signedIn(let user) = account.authState else { return }
        let circle = try await db.createCircle(name: name, creatorID: user.id)
        if case .loaded(let circles) = state {
            state = .loaded(circles + [CircleSummary(circle: circle, members: [user])])
        }
        sheetState = nil
    }

    /// Joins via invite code and grows the circle's bubble in place. Throws so
    /// the sheet can show the failure (bad code, network) and keep the input.
    @MainActor
    private func join(code: String) async throws {
        guard case .signedIn(let user) = account.authState else { return }
        let summary = try await db.joinCircle(code: code, userId: user.id)
        if case .loaded(let circles) = state, !circles.contains(where: { $0.id == summary.id }) {
            state = .loaded(circles + [summary])
        }
        sheetState = nil
    }
}

// MARK: - Bubble

/// The bubble's sphere — radial-gradient fill with a gloss highlight, like
/// light on a marble. Shared by the collage bubbles and the empty-state
/// backdrop so they always look like the same object.
private struct BubbleSurface: View {
    let tone: CircleBubbleLayout.BubbleTone
    let diameter: CGFloat

    var body: some View {
        ZStack {
            SwiftUI.Circle()
                .fill(RadialGradient(colors: [tone.hi, tone.lo],
                                     center: UnitPoint(x: 0.34, y: 0.28),
                                     startRadius: 0, endRadius: diameter * 0.75))
                .shadow(color: .black.opacity(0.18), radius: 13, y: 6)
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.32), .white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: diameter * 0.22))
                .frame(width: diameter * 0.44, height: diameter * 0.30)
                .offset(x: -diameter * 0.14, y: -diameter * 0.28)
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct CircleBubble: View {
    let summary: CircleSummary
    let slot: CircleBubbleLayout.Slot
    let scale: CGFloat
    let center: CGPoint
    /// Called with the tap point in the "root" coordinate space, so the
    /// ripple into the chat radiates from the finger.
    let onTap: (CGPoint) -> Void
    /// Slingshot release: the drag pull in design space (screen ÷ scale). The
    /// field converts this into an opposite-direction launch on the physics body.
    let onLaunch: (CGVector) -> Void

    /// Live drag translation (screen space) while stretching the spring; resets
    /// to zero on release, when the launch takes over.
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        let d = slot.diameter * scale
        ZStack {
                BubbleSurface(tone: slot.tone, diameter: d)
                VStack(spacing: 5 * scale) {
                    Text(summary.name)
                        .font(.system(size: min(23, max(12, slot.diameter * 0.135)) * scale,
                                      weight: .bold, design: .serif))
                        .foregroundStyle(slot.tone.fg)
                        .multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    if slot.diameter >= 84 {  // small bubbles drop the meta line, like the mockup
                        Text("\(summary.members.count) members")
                            .font(.system(size: 9.5 * scale, weight: .medium, design: .monospaced))
                            .foregroundStyle(slot.tone.fg.opacity(0.62))
                    }
                }
                .padding(.horizontal, 10 * scale)
        }
        .frame(width: d, height: d)
        .contentShape(SwiftUI.Circle())
        .onTapGesture(coordinateSpace: .named("root")) { location in
            onTap(location)
        }
        // Drag to stretch the spring; release to fling it the opposite way.
        // minimumDistance keeps small touches as taps (which open the circle).
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    onLaunch(CGVector(dx: value.translation.width / scale,
                                      dy: value.translation.height / scale))
                }
        )
        .position(x: center.x * scale, y: center.y * scale)
        .offset(x: drag.width, y: drag.height)
        .zIndex(slot.diameter)  // bigger bubbles float above smaller neighbors
    }
}

// MARK: - Join / Create pill

struct CirclePillButton: View {
    let title: String
    let filled: Bool
    var height: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Style.button)
                .foregroundStyle(filled ? Style.paper : Style.ink)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background {
                    if filled {
                        Capsule().fill(Style.ink)
                    } else {
                        Capsule().strokeBorder(Style.ink, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Create / Join sheet

/// One-field form sheet shared by Create (circle name) and Join (invite code):
/// text field — or fixed-length code boxes when codeLength is set — error
/// banner, confirm pill. The action is the caller's job, via onSubmit with the
/// trimmed input — a throw keeps the sheet open with the input intact and
/// shows the error.
private struct CircleFormSheet: View {
    let title: String
    let placeholder: String
    let cta: String
    let busyCta: String
    let errorPrefix: String
    var codeLength: Int? = nil
    // @MainActor-pinned: without it, Swift 5 mode lets this @Sendable async
    // closure run off the main actor, racing the reference counts of the
    // captured view/model on a background thread — a use-after-free that
    // faults in swift_retain (crash on createCircle's insert).
    let onSubmit: @MainActor (String) async throws -> Void

    @State private var input: String
    @State private var submitting = false
    @State private var error: String?

    init(title: String, placeholder: String, cta: String, busyCta: String,
         errorPrefix: String, codeLength: Int? = nil, initialInput: String = "",
         onSubmit: @escaping (String) async throws -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.cta = cta
        self.busyCta = busyCta
        self.errorPrefix = errorPrefix
        self.codeLength = codeLength
        self.onSubmit = onSubmit
        _input = State(initialValue: initialInput)
    }

    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var ready: Bool { codeLength.map { trimmed.count == $0 } ?? !trimmed.isEmpty }

    var body: some View {
        VStack(spacing: Style.Space.xl) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(Style.ink)
            if let codeLength {
                CodeField(length: codeLength, input: $input)
            } else {
                TextField(placeholder, text: $input)
                    .font(Style.field)
                    .autocorrectionDisabled()
                    .padding(.horizontal, Style.Space.lg).padding(.vertical, 12)
                    .background(Capsule().fill(Style.paper))
                    .overlay(Capsule().stroke(Style.rule, lineWidth: 1))
                    .onSubmit(submit)
            }
            if let error {
                ErrorBanner(message: error)
            }
            CirclePillButton(title: submitting ? busyCta : cta,
                             filled: true, height: 50, action: submit)
                .disabled(!ready || submitting)
                .opacity(!ready || submitting ? 0.35 : 1)
        }
        .padding(Style.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Style.chrome)
        .presentationDetents([.medium])
    }

    @MainActor
    private func submit() {
        guard ready, !submitting else { return }
        submitting = true
        error = nil
        Task { @MainActor in
            do {
                try await onSubmit(trimmed)
            } catch {
                self.error = "\(errorPrefix) — \(error.localizedDescription)"
            }
            submitting = false
        }
    }
}

/// One box per character of a fixed-length code. A hidden text field holds the
/// real input (so the system keyboard, paste, and deletion all just work); the
/// boxes only render it, with the cursor's box outlined in ink.
private struct CodeField: View {
    let length: Int
    @Binding var input: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $input)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused)
                .opacity(0)
                .frame(width: 1, height: 1)
            HStack(spacing: Style.Space.sm) {
                ForEach(0..<length, id: \.self) { i in
                    let chars = Array(input)
                    Text(i < chars.count ? String(chars[i]) : " ")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Style.ink)
                        .frame(width: 44, height: 54)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Style.paper))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(focused && i == chars.count ? Style.ink : Style.rule,
                                    lineWidth: focused && i == chars.count ? 1.5 : 1))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .onAppear { focused = true }
        .onChange(of: input) { _, new in
            let cleaned = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(length))
            if cleaned != new { input = cleaned }
        }
    }
}

// MARK: - Empty-state backdrop

// Drifting ghost bubbles behind the empty-state message — the same
// BubbleSurface the collage uses, faded, in the collage's own tones.
private struct FloatingBackdrop: View {
    private struct Dot {
        let toneIndex: Int, diameter: CGFloat, opacity: Double, duration: Double
        /// Center position given the field size (mockup edge-anchored offsets).
        let center: (CGSize) -> CGPoint
    }

    private static let dots: [Dot] = [
        Dot(toneIndex: 0, diameter: 120, opacity: 0.55, duration: 7,
            center: { _ in CGPoint(x: 30, y: 80) }),
        Dot(toneIndex: 1, diameter: 90, opacity: 0.6, duration: 6,
            center: { CGPoint(x: $0.width - 5, y: 125) }),
        Dot(toneIndex: 2, diameter: 70, opacity: 0.55, duration: 8,
            center: { CGPoint(x: 55, y: $0.height - 155) }),
        Dot(toneIndex: 3, diameter: 140, opacity: 0.5, duration: 9,
            center: { CGPoint(x: $0.width - 100, y: $0.height - 130) }),
        Dot(toneIndex: 4, diameter: 50, opacity: 0.6, duration: 6.5,
            center: { CGPoint(x: $0.width / 2 + 25, y: $0.height * 0.4 + 25) }),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(Self.dots.enumerated()), id: \.offset) { i, dot in
                FloatingDot(dot: dot, startsHigh: i.isMultiple(of: 2))
                    .position(dot.center(geo.size))
            }
        }
    }

    private struct FloatingDot: View {
        let dot: Dot
        let startsHigh: Bool
        @State private var up = false

        var body: some View {
            BubbleSurface(tone: CircleBubbleLayout.slots[dot.toneIndex].tone,
                          diameter: dot.diameter)
                .opacity(dot.opacity)
                .offset(y: (up != startsHigh) ? 8 : -8)
                .onAppear {
                    withAnimation(.easeInOut(duration: dot.duration)
                        .repeatForever(autoreverses: true)) { up = true }
                }
        }
    }
}

// MARK: - Preview

#Preview {
    let user = { (name: String) in
        User(id: UUID(), username: name, bio: nil, avatarUrl: nil, role: nil,
             followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    }
    let circle = { (name: String, memberNames: [String]) in
        CircleSummary(circle: Circle(id: UUID(), name: name, createdBy: nil, createdAt: nil,
                                     inviteCode: "ABC123"),
                      members: memberNames.map(user))
    }
    let db = DatabaseService()
    return CirclesView(db: db, account: AccountManager(db: db), initial: .loaded([
        circle("Dean", ["Dave Smith", "Arnell R", "Sawyer W", "Phil H", "Mia G", "Tom L"]),
        circle("Spiritual Miracles", ["Ben B", "Tom L", "Jess R"]),
    ]), onEnter: { _, _, _ in })
}
