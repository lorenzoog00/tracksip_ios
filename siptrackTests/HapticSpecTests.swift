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

    // MARK: - advanceIntensity

    @Test func advanceIntensity_zeroDelta_isGentle() {
        #expect(HapticSpec.advanceIntensity(bacDelta: 0) <= 0.35)
    }

    @Test func advanceIntensity_risesWithDelta() {
        let small = HapticSpec.advanceIntensity(bacDelta: 0.005)
        let large = HapticSpec.advanceIntensity(bacDelta: 0.040)
        #expect(large > small)
    }

    @Test func advanceIntensity_clampsToUnitRange() {
        #expect(HapticSpec.advanceIntensity(bacDelta: 5.0) <= 1.0)
        #expect(HapticSpec.advanceIntensity(bacDelta: -5.0) >= 0.0)
    }

    @Test func advanceIntensity_usesMagnitudeNotSign() {
        // Going down 0.02 is as notable as going up 0.02.
        #expect(HapticSpec.advanceIntensity(bacDelta: -0.02) == HapticSpec.advanceIntensity(bacDelta: 0.02))
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
}
