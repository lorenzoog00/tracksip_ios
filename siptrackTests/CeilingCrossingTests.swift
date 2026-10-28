//
//  CeilingCrossingTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// The ceiling-crossed haptic fires once per night, and that has to hold across a
// force-quit, so the ids of the nights that have fired are kept on disk. These
// tests go through the real DataStore, which reads and writes a real file in the
// app's documents directory: one piece of global state shared by every test in
// the process. Two things keep them from leaking into each other or into
// whatever runs next (or into a developer's simulator):
//
//   - `.serialized`: Swift Testing runs tests in parallel by default, and the
//     tests below share the same files.
//   - Each test snapshots the files it touches byte for byte before touching
//     them and, in a `defer`, puts them back exactly: same bytes if they were
//     there, no file if not.
//
// `@MainActor`: DataStore and AppState live in an app module that defaults to
// MainActor isolation, and this test target does not. Isolating the suite makes
// every call below legal however the compiler infers the app types, and matches
// production, where all of this code runs on the main actor.
@Suite(.serialized) @MainActor
struct CeilingCrossingTests {

    /// A DataStore file as it stood when the test began. Defaults to the crossed-ids
    /// file.
    ///
    /// DataStore keeps its file paths private, so this restates the convention
    /// (`<documents>/<key>.json`). The first test asserts the crossed-ids file really
    /// appears at this URL after a save, so a renamed key fails loudly instead of
    /// leaving the snapshot watching the wrong file.
    private struct FileSnapshot {
        let fileURL: URL
        private let original: Data?

        init(key: String = "siptrack_ceiling_crossed") {
            let url = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("\(key).json")
            fileURL = url
            original = try? Data(contentsOf: url)
        }

        /// Leaves the store as a fresh install finds it: no file at all.
        func remove() {
            try? FileManager.default.removeItem(at: fileURL)
        }

        func restore() {
            if let original {
                try? original.write(to: fileURL, options: .atomic)
            } else {
                remove()
            }
        }
    }

    // MARK: - Persistence

    @Test func crossedEventId_survivesRelaunch_andKeepsTheCeilingLatched() {
        let snapshot = FileSnapshot()
        defer { snapshot.restore() }
        snapshot.remove()

        DataStore.shared.saveCeilingCrossedEventIds(["night-1"])
        #expect(FileManager.default.fileExists(atPath: snapshot.fileURL.path))

        // DataStore holds nothing in memory: every load re-reads the file, which is
        // exactly what a relaunched process does. Save then load is the relaunch.
        let reloaded = DataStore.shared.loadCeilingCrossedEventIds()
        #expect(reloaded.contains("night-1"))

        // The crossing the live tick would see on relaunch: 0.048 -> 0.052 over a
        // 0.05 ceiling. It stays silent for the night that already fired...
        let firedNight = HapticSpec.crossingFires(
            previousBAC: 0.048, currentBAC: 0.052, ceiling: 0.05,
            alreadyFired: reloaded.contains("night-1")
        )
        #expect(firedNight == false)

        // ...and the same crossing does fire for a night that is not in the set, so
        // the silence above comes from the persisted id and not from the inputs.
        let freshNight = HapticSpec.crossingFires(
            previousBAC: 0.048, currentBAC: 0.052, ceiling: 0.05,
            alreadyFired: reloaded.contains("night-2")
        )
        #expect(freshNight == true)
    }

    @Test func loadingFromAnEmptyStore_returnsAnEmptySet() {
        let snapshot = FileSnapshot()
        defer { snapshot.restore() }
        snapshot.remove()

        // No file at all, as on a fresh install or right after sign-out.
        let ids = DataStore.shared.loadCeilingCrossedEventIds()
        #expect(ids.isEmpty)
    }

    // MARK: - Pruning

    /// Every file `DataStore.deleteEvent` reads and rewrites. Snapshotting all of
    /// them keeps a delete test from touching a developer's real events, entries,
    /// water or food.
    private static let deleteEventKeys = [
        "siptrack_ceiling_crossed", "siptrack_events", "siptrack_entries",
        "siptrack_water", "siptrack_food",
    ]

    @Test func deletingAnEvent_forgetsItsCrossedId() {
        let snapshots = Self.deleteEventKeys.map { FileSnapshot(key: $0) }
        defer { snapshots.forEach { $0.restore() } }
        snapshots.forEach { $0.remove() }

        DataStore.shared.saveCeilingCrossedEventIds(["night-1", "night-2"])
        DataStore.shared.deleteEvent("night-1")

        #expect(DataStore.shared.loadCeilingCrossedEventIds() == ["night-2"])
    }

    @Test func deletingAnEventThatNeverFired_createsNoCrossedFile() {
        let snapshots = Self.deleteEventKeys.map { FileSnapshot(key: $0) }
        defer { snapshots.forEach { $0.restore() } }
        snapshots.forEach { $0.remove() }

        DataStore.shared.deleteEvent("night-3")

        let crossedFile = snapshots[0].fileURL
        #expect(!FileManager.default.fileExists(atPath: crossedFile.path))
    }

    // MARK: - Ceiling resolution

    /// A night as CreateEventView builds it: a driving night carries `bacLimit`, any
    /// night may carry a personal `targetBAC`.
    private func night(targetBAC: Double?, bacLimit: Double?) -> NightEvent {
        NightEvent(
            id: "night", startTime: Date(), drivingMode: bacLimit != nil,
            bacLimit: bacLimit, targetBAC: targetBAC, createdAt: Date()
        )
    }

    @Test func ceiling_prefersThePersonalTarget() {
        #expect(AppState.ceiling(for: night(targetBAC: 0.05, bacLimit: 0.08)) == 0.05)
    }

    @Test func ceiling_fallsBackToTheDrivingLimit() {
        #expect(AppState.ceiling(for: night(targetBAC: nil, bacLimit: 0.08)) == 0.08)
    }

    @Test func ceiling_isNilWhenTheNightSetsNeither() {
        // Most nights. No legal-limit fallback: the haptic only ever fires for a
        // ceiling the user chose, so a night with none must fire nothing.
        #expect(AppState.ceiling(for: night(targetBAC: nil, bacLimit: nil)) == nil)
    }
}
