//
//  BubblePhysicsTests.swift
//  CircleMagazineTests
//
//  The bubble field's toy physics: colliding bubbles must separate and
//  rebound, and walls must keep every bubble inside the field.
//

import CoreGraphics
import Testing
@testable import CircleMagazine

struct BubblePhysicsTests {
    @Test func collidingBubblesSeparateAndRebound() {
        let p = BubblePhysics()
        p.sync(count: 2)  // seeds bounds; bodies replaced below
        p.bodies = [
            .init(pos: CGPoint(x: 100, y: 300), vel: CGVector(dx: 10, dy: 0), radius: 50),
            .init(pos: CGPoint(x: 160, y: 300), vel: CGVector(dx: -10, dy: 0), radius: 50),
        ]
        p.step(dt: 1 / 60)

        let a = p.bodies[0], b = p.bodies[1]
        // Pushed out of overlap…
        #expect(b.pos.x - a.pos.x >= 99.9)
        // …and equal masses swap velocities head-on: both now receding.
        #expect(a.vel.dx == -10)
        #expect(b.vel.dx == 10)
    }

    @Test func slingshotLaunchesOppositeWithEqualForce() {
        let p = BubblePhysics()
        p.sync(count: 1)
        p.bodies = [.init(pos: CGPoint(x: 100, y: 300), vel: CGVector(dx: 0, dy: 0), radius: 40)]
        p.slingshot(0, pull: CGVector(dx: 30, dy: -20), launch: 6)

        // Bubble sits at the stretched (pulled) position…
        #expect(p.bodies[0].pos.x == 130)
        #expect(p.bodies[0].pos.y == 280)
        // …and launches the opposite way, force proportional to the stretch.
        #expect(p.bodies[0].vel.dx == -180)   // -30 * 6
        #expect(p.bodies[0].vel.dy == 120)    //  20 * 6
    }

    @Test func wallsKeepBubblesInBounds() {
        let p = BubblePhysics()
        p.sync(count: 1)  // bounds = 390 x 600
        p.bodies = [.init(pos: CGPoint(x: 10, y: 300), vel: CGVector(dx: -50, dy: 0), radius: 40)]
        p.step(dt: 1 / 60)

        #expect(p.bodies[0].pos.x == 40)     // clamped to the left wall
        #expect(p.bodies[0].vel.dx == 50)    // reflected back in
    }
}
