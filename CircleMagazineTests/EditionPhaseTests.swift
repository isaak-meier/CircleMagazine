//
//  EditionPhaseTests.swift
//  CircleMagazineTests
//
//  Which phase a circle renders: a live edition is the magazine, nothing live
//  is the compose phase (chat), and a real failure still reads as a failure.
//  Serialized — the debug override lives in shared UserDefaults.
//

import Foundation
import Testing
@testable import CircleMagazine

@MainActor
@Suite(.serialized)
struct EditionPhaseTests {
    /// A VM over a frozen store, with the debug override set for its lifetime.
    private func vm(store state: IssueLoadState, forceCompose: Bool = false) -> IssueViewModel {
        UserDefaults.standard.set(forceCompose, forKey: IssueViewModel.forceComposeKey)
        defer { UserDefaults.standard.removeObject(forKey: IssueViewModel.forceComposeKey) }
        return .preview(state)
    }

    private func phase(_ state: IssueLoadState) -> String {
        switch state {
        case .loading:      "loading"
        case .loaded:       "loaded"
        case .composing:    "composing"
        case .failedToLoad: "failed"
        }
    }

    @Test func liveEditionReadsAsLoaded() {
        #expect(phase(vm(store: .loaded(Magazine.sample)).state) == "loaded")
    }

    @Test func nothingLiveReadsAsComposing() {
        #expect(phase(vm(store: .composing).state) == "composing")
    }

    @Test func failureIsNotAPhase() {
        #expect(phase(vm(store: .failedToLoad(error: "offline")).state) == "failed")
    }

    @Test func debugToggleForcesComposeOverALiveEdition() {
        #expect(phase(vm(store: .loaded(Magazine.sample), forceCompose: true).state) == "composing")
    }

    @Test func debugToggleOffLeavesTheLiveEditionAlone() {
        #expect(phase(vm(store: .loaded(Magazine.sample), forceCompose: false).state) == "loaded")
    }
}
