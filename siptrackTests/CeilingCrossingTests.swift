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
//     tests below share the same files. Note what this does NOT cover: it orders
//     tests *within* this suite only. Different suites still run in parallel in
//     the same process, so a second suite that touched `DataStore` or the
//     documents directory would collide with this one silently, with no ordering
//     to appeal to. This is currently the only suite that does. Anything new
//     that needs those files belongs in here, or needs a shared lock.
//   - Each test moves the files it touches aside before touching them and, in a
//     `defer`, moves them back: same bytes if they were there, no file if not.
//     Moving rather than deleting is deliberate — see `FileSnapshot`.
//
// `@MainActor`: DataStore and AppState live in an app module that defaults to
// MainActor isolation, and this test target does not. Isolating the suite makes
// every call below legal however the compiler infers the app types, and matches
// production, where all of this code runs on the main actor.
@Suite(.serialized) @MainActor
struct CeilingCrossingTests {

    /// A DataStore file moved aside for the duration of a test. Defaults to the
    /// crossed-ids file.
    ///
    /// DataStore keeps its file paths private, so this restates the convention
    /// (`<documents>/<key>.json`). The first test asserts the crossed-ids file really
    /// appears at this URL after a save, so a renamed key fails loudly instead of
    /// leaving the snapshot watching the wrong file.
    ///
    /// These are real files in the real app container, so a developer running this
    /// suite on a simulator they also use as the app is running it over their own
    /// nights — and device-feel tuning on this branch means exactly that simulator.
    /// So `remove()` renames rather than deletes: the data sits next door as
    /// `<key>.json.testbak` until `restore()` puts it back. Nothing is held in
    /// memory and nothing depends on `restore()` being reached, which matters
    /// because a `defer` is skipped by `Cmd-.`, by a `fatalError` anywhere in the
    /// process, and by a debugger kill. Worst case the night survives under a
    /// visible name and can be renamed back by hand.
    private struct FileSnapshot {
        let fileURL: URL

        /// Where `remove()` parks the file. A sibling of the original, so the move
        /// stays within one volume and cannot fall back to a copy.
        private var backupURL: URL { fileURL.appendingPathExtension("testbak") }

        init(key: String = "siptrack_ceiling_crossed") {
            fileURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("\(key).json")
        }

        /// Leaves the store as a fresh install finds it: no file at the real path.
        /// Clears any backup a previous interrupted run left behind first, since
        /// `moveItem` refuses to overwrite. Both calls are no-ops when the file is
        /// absent, which is the common case on a clean test machine.
        func remove() {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
        }

        /// Puts the file back exactly: the original bytes if there was a file, and
        /// no file at all if there was not. Whatever the test wrote at the real
        /// path is discarded first, or the move would refuse.
        func restore() {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.moveItem(at: backupURL, to: fileURL)
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
