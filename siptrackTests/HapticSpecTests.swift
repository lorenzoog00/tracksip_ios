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
}
