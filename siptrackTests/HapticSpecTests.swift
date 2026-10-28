//
//  HapticSpecTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

struct HapticSpecTests {

    // MARK: - shouldPlay

    @Test func shouldPlay_requiresBothEnabledAndSupported() {
        #expect(HapticSpec.shouldPlay(enabled: true,  supportsHaptics: true)  == true)
        #expect(HapticSpec.shouldPlay(enabled: false, supportsHaptics: true)  == false)
        #expect(HapticSpec.shouldPlay(enabled: true,  supportsHaptics: false) == false)
    }

    // MARK: - advanceSharpness

    @Test func advanceSharpness_zeroDelta_isDull() {
        #expect(HapticSpec.advanceSharpness(bacDelta: 0) <= 0.35)
    }

    @Test func advanceSharpness_risesWithDelta() {
        let small = HapticSpec.advanceSharpness(bacDelta: 0.005)
        let large = HapticSpec.advanceSharpness(bacDelta: 0.040)
        #expect(large > small)
    }

    @Test func advanceSharpness_clampsToUnitRange() {
        #expect(HapticSpec.advanceSharpness(bacDelta: 5.0) <= 1.0)
        #expect(HapticSpec.advanceSharpness(bacDelta: -5.0) >= 0.0)
    }

    @Test func advanceSharpness_usesMagnitudeNotSign() {
        // Going down 0.02 is as notable as going up 0.02.
        #expect(HapticSpec.advanceSharpness(bacDelta: -0.02) == HapticSpec.advanceSharpness(bacDelta: 0.02))
    }

    @Test func advanceSharpness_nanDelta_staysInRange() {
        // Swift's min(NaN, 1.0) returns NaN, so without the guard a NaN delta
        // would reach CoreHaptics as a NaN sharpness. It must read as "no change".
        let sharpness = HapticSpec.advanceSharpness(bacDelta: .nan)
        #expect(!sharpness.isNaN)
        #expect(sharpness == 0.2)
    }

    // MARK: - crossingFires

    @Test func crossingFires_onUpwardCross() {
        #expect(HapticSpec.crossingFires(previousBAC: 0.048, currentBAC: 0.052, ceiling: 0.05, alreadyFired: false) == true)
    }

    @Test func crossingFires_notWhileStayingAbove() {
        // The tick after the crossing must be silent.
        #expect(HapticSpec.crossingFires(previousBAC: 0.052, currentBAC: 0.061, ceiling: 0.05, alreadyFired: true) == false)
    }

    @Test func crossingFires_onlyOncePerNight_evenAfterDroppingBackUnder() {
        #expect(HapticSpec.crossingFires(previousBAC: 0.041, currentBAC: 0.058, ceiling: 0.05, alreadyFired: true) == false)
    }

    @Test func crossingFires_neverWhenNoCeilingSet() {
        #expect(HapticSpec.crossingFires(previousBAC: 0.0, currentBAC: 0.20, ceiling: nil, alreadyFired: false) == false)
    }

    @Test func crossingFires_notWhenAlreadyAboveAtFirstObservation() {
        // previous == current happens on the first tick after a cold launch.
        #expect(HapticSpec.crossingFires(previousBAC: 0.09, currentBAC: 0.09, ceiling: 0.05, alreadyFired: false) == false)
    }

    @Test func crossingFires_notOnDownwardCross() {
        #expect(HapticSpec.crossingFires(previousBAC: 0.061, currentBAC: 0.044, ceiling: 0.05, alreadyFired: false) == false)
    }

    @Test func crossingFires_notWhenColdLaunchAlreadyAboveAndStillRising() {
        // Cold launch above the ceiling, latch not set yet, BAC still climbing:
        // only the edge condition keeps this silent, since alreadyFired is false.
        #expect(HapticSpec.crossingFires(previousBAC: 0.052, currentBAC: 0.061, ceiling: 0.05, alreadyFired: false) == false)
    }

    // MARK: - crossingFires boundaries

    @Test func crossingFires_notWhenPreviousIsExactlyAtCeiling() {
        // Strict edge: sitting exactly on the ceiling already counts as reached.
        #expect(HapticSpec.crossingFires(previousBAC: 0.05, currentBAC: 0.06, ceiling: 0.05, alreadyFired: false) == false)
    }

    @Test func crossingFires_firesWhenCurrentLandsExactlyOnCeiling() {
        // Reaching the ceiling counts as crossing it.
        #expect(HapticSpec.crossingFires(previousBAC: 0.048, currentBAC: 0.05, ceiling: 0.05, alreadyFired: false) == true)
    }

    @Test func crossingFires_neverForAZeroToleranceCeiling() {
        // A driving night in a novice or commercial tier resolves to a ceiling of
        // exactly 0.00 (Australia, Brazil, Canada, Chile novice; Argentina
        // commercial). Any first sip clears it, and alarming there is noise. Safe
        // today only because BACCalculator clamps BAC to >= 0, which this does not
        // rely on.
        #expect(HapticSpec.crossingFires(previousBAC: 0.0, currentBAC: 0.01, ceiling: 0.0, alreadyFired: false) == false)
    }

    // MARK: - firstObservationFires

    @Test func firstObservationFires_whenResumedAboveAnUnannouncedCeiling() {
        // The case no edge test can catch: the crossing happened while the process
        // was dead, so nothing is on disk and this is the only chance to announce it.
        #expect(HapticSpec.firstObservationFires(currentBAC: 0.07, ceiling: 0.05, alreadyFired: false) == true)
    }

    @Test func firstObservationFires_notWhenTheNightAlreadyAnnounced() {
        // Same BAC, same ceiling; only the persisted latch differs. This is the
        // distinction the crossed-ids file exists to make.
        #expect(HapticSpec.firstObservationFires(currentBAC: 0.07, ceiling: 0.05, alreadyFired: true) == false)
    }

    @Test func firstObservationFires_notWhenBelowTheCeiling() {
        // A night resumed under its ceiling waits for a real upward edge.
        #expect(HapticSpec.firstObservationFires(currentBAC: 0.04, ceiling: 0.05, alreadyFired: false) == false)
    }

    @Test func firstObservationFires_firesWhenExactlyOnTheCeiling() {
        // Matches crossingFires: reaching the ceiling counts as reaching it.
        #expect(HapticSpec.firstObservationFires(currentBAC: 0.05, ceiling: 0.05, alreadyFired: false) == true)
    }

    @Test func firstObservationFires_neverWhenNoCeilingSet() {
        #expect(HapticSpec.firstObservationFires(currentBAC: 0.20, ceiling: nil, alreadyFired: false) == false)
    }

    @Test func firstObservationFires_neverForAZeroToleranceCeiling() {
        #expect(HapticSpec.firstObservationFires(currentBAC: 0.01, ceiling: 0.0, alreadyFired: false) == false)
    }

    // MARK: - selectionChanged

    @Test func selectionChanged_offToOff_isSilent() {
        // A touch in the off zone while already off.
        #expect(HapticSpec.selectionChanged(from: nil, to: nil) == false)
    }

    @Test func selectionChanged_offToValue_ticks() {
        #expect(HapticSpec.selectionChanged(from: nil, to: 0.05) == true)
    }

    @Test func selectionChanged_valueToOff_ticks() {
        // The off transition must tick: nothing else in the UI confirms it.
        #expect(HapticSpec.selectionChanged(from: 0.05, to: nil) == true)
    }

    @Test func selectionChanged_notchToDifferentNotch_ticks() {
        #expect(HapticSpec.selectionChanged(from: 0.05, to: 0.055) == true)
    }

    @Test func selectionChanged_sameValue_isSilent() {
        // Touch-down on the notch already selected, or dragging past a clamped end.
        #expect(HapticSpec.selectionChanged(from: 0.05, to: 0.05) == false)
        #expect(HapticSpec.selectionChanged(from: 0.2, to: 0.2) == false)
    }

    @Test func selectionChanged_buttonCeilingMatchesTenthNotch() {
        // "Set a ceiling" writes the literal 0.05; the slider reaches that notch as
        // 10 * 0.005. Exact equality only works if those are the same Double.
        let tenthNotch = 10.0 * 0.005
        #expect(HapticSpec.selectionChanged(from: 0.05, to: tenthNotch) == false)
    }
}
