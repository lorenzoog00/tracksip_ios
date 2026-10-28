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
//   - `.serialized`: Swift Testing runs tests in parallel by default, and both
//     tests below use the same file.
//   - Each test snapshots that file byte for byte before touching it and, in a
//     `defer`, puts it back exactly: same bytes if it was there, no file if not.
@Suite(.serialized)
struct CeilingCrossingTests {

    /// The crossed-ids file as it stood when the test began.
    ///
    /// DataStore keeps its file paths private, so this restates the convention
    /// (`<documents>/<key>.json`). The first test asserts the file really appears
    /// at this URL after a save, so a renamed key fails loudly instead of leaving
    /// the snapshot watching the wrong file.
    private struct FileSnapshot {
        let fileURL: URL
        private let original: Data?

        init() {
            let url = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("siptrack_ceiling_crossed.json")
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
}
