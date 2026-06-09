//
//  DriveVerdictTests.swift
//  siptrackTests
//
//  Conservative, never-affirmative drive verdict.
//

import Testing
@testable import siptrack

struct DriveVerdictTests {

    @Test func verdictBAC_usesUpperBandOrPeak() {
        // Descending: upper edge of the ±20% band dominates.
        #expect(abs(BACCalculator.driveVerdictBAC(current: 0.05, projectedPeak: 0.05) - 0.06) < 1e-9)
        // Rising: the projected peak dominates.
        #expect(BACCalculator.driveVerdictBAC(current: 0.05, projectedPeak: 0.09) == 0.09)
    }

    @Test func impairmentTier_fivePercentIsDangerEvenUnderLegalEighty() {
        // 0.06 verdict, legal limit 0.08 → still "impaired" (do not drive).
        #expect(BACCalculator.impairmentTier(verdictBAC: 0.06, legalLimit: 0.08) == .impaired)
    }

    @Test func impairmentTier_overLegal_andMildAndMinimal() {
        #expect(BACCalculator.impairmentTier(verdictBAC: 0.09, legalLimit: 0.08) == .overLegal)
        #expect(BACCalculator.impairmentTier(verdictBAC: 0.03, legalLimit: 0.08) == .mild)
        #expect(BACCalculator.impairmentTier(verdictBAC: 0.01, legalLimit: 0.08) == .minimal)
    }
}
