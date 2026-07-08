//
//  CircleBubbleLayoutTests.swift
//  CircleMagazineTests
//
//  The bubble collage cycles 7 fixed slots; these pin the wrap-around math.
//

import CoreGraphics
import Testing
@testable import CircleMagazine

struct CircleBubbleLayoutTests {
    @Test func slotsCycleAndDescend() {
        let slots = CircleBubbleLayout.slots
        // Biggest-first, so rank order reads as size order.
        #expect(slots.map(\.diameter) == slots.map(\.diameter).sorted(by: >))
        // 8th circle wraps to slot 0, one field height down.
        let wrapped = CircleBubbleLayout.slot(slots.count)
        #expect(wrapped.diameter == slots[0].diameter)
        #expect(wrapped.y == slots[0].y + CircleBubbleLayout.cycleHeight)
    }

    @Test func fieldHeightGrowsPerCycle() {
        #expect(CircleBubbleLayout.fieldHeight(count: 0) == CircleBubbleLayout.cycleHeight)
        #expect(CircleBubbleLayout.fieldHeight(count: 7) == CircleBubbleLayout.cycleHeight)
        #expect(CircleBubbleLayout.fieldHeight(count: 8) == CircleBubbleLayout.cycleHeight * 2)
    }
}
