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

struct CirclesView: View {
    let db: DatabaseService
    let account: AccountManager
    /// False while another tab is showing — pauses the bubble simulation.
    var active = true
    /// Bubble tapped: the circle, its tone, and the tap point in the
    /// "root" coordinate space — RootTabView ripples into the chat from there.
    let onEnter: (CircleSummary, CircleBubbleLayout.BubbleTone, CGPoint) -> Void

    enum LoadState { case loading, loaded([CircleSummary]), failed(String) }
    @State private var state: LoadState
    @State private var physics = BubblePhysics()

    init(db: DatabaseService, account: AccountManager, active: Bool = true,
         initial: LoadState = .loading,
         onEnter: @escaping (CircleSummary, CircleBubbleLayout.BubbleTone, CGPoint) -> Void) {
        self.db = db
        self.account = account
        self.active = active
        self.onEnter = onEnter
        _state = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            Masthead(title: "Circles", stamp: stampText, eyebrow: "YOU BELONG TO")
            legendRow
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
                Spacer()
                Text("You don't belong to any circles yet.")
                    .font(Style.body).foregroundStyle(Style.meta)
                Spacer()
            case .loaded(let circles):
                bubbleField(circles)
            }
        }
        .background(Style.chrome)
        .task { await load() }
    }

    private var stampText: String? {
        guard case .loaded(let circles) = state, !circles.isEmpty else { return nil }
        return "\(circles.count) CIRCLE\(circles.count == 1 ? "" : "S")"
    }

    private var legendRow: some View {
        HStack {
            Text("YOUR CIRCLES")
                .foregroundStyle(Color(hex: 0x9A958E))
            Spacer()
            Text("TAP TO ENTER")
                .foregroundStyle(Color(hex: 0xB84C4C))
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .tracking(1.2)
        .padding(.horizontal, Style.Space.lg)
        .padding(.vertical, Style.Space.sm)
    }

    private func bubbleField(_ circles: [CircleSummary]) -> some View {
        let ranked = circles.sorted { $0.members.count > $1.members.count }
        physics.sync(count: ranked.count)
        return GeometryReader { geo in
            let scale = geo.size.width / CircleBubbleLayout.designWidth
            ScrollView {
                TimelineView(.animation(minimumInterval: nil, paused: !active)) { timeline in
                    let _ = physics.tick(to: timeline.date)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { i, summary in
                            let slot = CircleBubbleLayout.slot(i)
                            CircleBubble(summary: summary, slot: slot, scale: scale,
                                         center: physics.bodies[i].pos) { tapPoint in
                                onEnter(summary, slot.tone, tapPoint)
                            }
                        }
                    }
                    .frame(width: geo.size.width,
                           height: physics.bounds.height * scale,
                           alignment: .topLeading)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

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
}

// MARK: - Bubble

private struct CircleBubble: View {
    let summary: CircleSummary
    let slot: CircleBubbleLayout.Slot
    let scale: CGFloat
    let center: CGPoint
    /// Called with the tap point in the "root" coordinate space, so the
    /// ripple into the chat radiates from the finger.
    let onTap: (CGPoint) -> Void

    var body: some View {
        let d = slot.diameter * scale
        ZStack {
                SwiftUI.Circle()
                    .fill(RadialGradient(colors: [slot.tone.hi, slot.tone.lo],
                                         center: UnitPoint(x: 0.34, y: 0.28),
                                         startRadius: 0, endRadius: d * 0.75))
                    .shadow(color: .black.opacity(0.18), radius: 13, y: 6)
                // Gloss highlight, top-left, like light on a marble.
                Ellipse()
                    .fill(RadialGradient(colors: [.white.opacity(0.32), .white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: d * 0.22))
                    .frame(width: d * 0.44, height: d * 0.30)
                    .offset(x: -d * 0.14, y: -d * 0.28)
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
        .position(x: center.x * scale, y: center.y * scale)
        .zIndex(slot.diameter)  // bigger bubbles float above smaller neighbors
    }
}

// MARK: - Preview

#Preview {
    let user = { (name: String) in
        User(id: UUID(), username: name, bio: nil, avatarUrl: nil, role: nil,
             followCredits: nil, circleSlots: nil, isVerified: nil, createdAt: nil)
    }
    let circle = { (name: String, memberNames: [String]) in
        CircleSummary(circle: Circle(id: UUID(), name: name, createdBy: nil, createdAt: nil),
                      members: memberNames.map(user))
    }
    let db = DatabaseService()
    return CirclesView(db: db, account: AccountManager(db: db), initial: .loaded([
        circle("Dean", ["Dave Smith", "Arnell R", "Sawyer W", "Phil H", "Mia G", "Tom L"]),
        circle("Sunday Roast", ["Mia G", "Tom L", "Jess R"]),
        circle("Ridgeline", ["Kate B", "Nick R"]),
        circle("Analog Heads", ["Elle L"]),
        circle("The Archive", ["Arnell R", "Dave Smith", "Mia G", "Kate B"]),
        circle("Cold Plunge", ["Sawyer W", "Tom L", "Jess R", "Phil H", "Elle L"]),
        circle("Night Shift", ["Phil H", "Elle L"]),
    ]), onEnter: { _, _, _ in })
}
