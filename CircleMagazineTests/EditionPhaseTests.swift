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

    // MARK: - The publish boundary
    //
    // Liveness is derived from `publish_date` rather than stored, so the whole
    // weekly cycle turns on one comparison: the live queries keep editions
    // strictly *before* `liveCutoff`, drafts from it onward. These pin the
    // Saturday→Sunday edge that comparison has to land on. Flipping `<` to
    // `<=` (publishing a day early, and stranding compose with no draft to
    // submit into) fails here.

    /// Local calendar throughout — `publishDate` formats in the device's zone,
    /// so a UTC-pinned input would only pass in UTC.
    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day,
                                                   hour: hour))!
    }

    /// Saturday itself: the edition closing tonight is still being assembled.
    @Test func anEditionIsNotLiveOnTheSaturdayItCloses() {
        let saturday = day(2026, 8, 1)
        let stamp = Issue.publishDate(for: EditionCountdown.publishDay(after: saturday))
        #expect(stamp == "2026-08-01")              // it is this Saturday's edition
        #expect(!(stamp < Issue.liveCutoff(now: saturday)))   // …and not yet live
        #expect(stamp >= Issue.liveCutoff(now: saturday))     // still the open draft
    }

    /// Circle Sunday: the same edition is now the magazine.
    @Test func theEditionGoesLiveOnSunday() {
        let stamp = "2026-08-01"
        #expect(stamp < Issue.liveCutoff(now: day(2026, 8, 2)))
    }

    /// Every issue is on exactly one side of the cutoff — no edition can be both
    /// live and draft, and none can be neither.
    @Test func liveAndDraftFiltersPartitionEveryEdition() {
        let cutoff = Issue.liveCutoff(now: day(2026, 8, 2))
        for stamp in ["2026-06-17", "2026-08-01", "2026-08-02", "2026-08-08"] {
            #expect((stamp < cutoff) != (stamp >= cutoff))
        }
    }

    // MARK: - What compose tells the author
    //
    // Posting mid-week and then finding nothing in the live edition is the most
    // confusing thing about the weekly cycle, so compose names both the edition
    // and the day it opens. These pin that the two are the Saturday and the
    // Sunday after it — the same pair the queries partition on.

    @Test func composeNamesTheEditionByItsSaturday() {
        let wednesday = day(2026, 7, 29)
        #expect(EditionCountdown.editionName(after: wednesday) == "August 1")
    }

    @Test func composeNamesTheSundayTheEditionOpens() {
        let wednesday = day(2026, 7, 29)
        #expect(EditionCountdown.opensOn(after: wednesday) == "Sunday, August 2")
    }

    /// The named day and the day it opens must stay one apart, and the edition's
    /// own stamp must match the name — otherwise compose promises one date and
    /// the masthead shows another.
    @Test func theNamedEditionMatchesTheStampItWillBeSavedWith() {
        for day in 27...31 {
            let now = self.day(2026, 7, day)
            let stamp = Issue.publishDate(for: EditionCountdown.publishDay(after: now))
            #expect(stamp == "2026-08-01")
            #expect(EditionCountdown.editionName(after: now) == "August 1")
            #expect(EditionCountdown.opensOn(after: now) == "Sunday, August 2")
            // …and that promised day is exactly when the stamp goes live.
            #expect(stamp < Issue.liveCutoff(now: self.day(2026, 8, 2)))
            #expect(!(stamp < Issue.liveCutoff(now: self.day(2026, 8, 1))))
        }
    }
}
