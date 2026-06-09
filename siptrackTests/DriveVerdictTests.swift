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

    private func ctx(verdict: Double, current: Double, prev: Double, limit: Double = 0.08) -> WarningContext {
        WarningContext(
            currentBAC: current, previousBAC: prev, drivingMode: true, bacLimit: limit,
            drinksLastHour: 1, totalCalories: 0,
            previousStage: IntoxicationStage.stage(for: prev),
            currentStage: IntoxicationStage.stage(for: current),
            prefs: NotificationPreferences(), eliminationRate: 0.015, verdictBAC: verdict)
    }

    @Test func warnings_neverAffirmSafeToDrive_belowImpairment() {
        let ws = buildWarnings(context: ctx(verdict: 0.012, current: 0.01, prev: 0.0))
        // No "Do Not Drive" and no danger-level affirmation; minimal tier stays silent here.
        #expect(!ws.contains { $0.kind == .bacExceeded })
        #expect(!ws.contains { $0.message.localizedCaseInsensitiveContains("safe to drive at") })
    }

    @Test func warnings_fivePercentUnderLegal_isDoNotDrive() {
        let ws = buildWarnings(context: ctx(verdict: 0.06, current: 0.05, prev: 0.04))
        #expect(ws.contains { $0.title == "Do Not Drive" })
    }

    @Test func warnings_mildTier_warnsButDoesNotAffirm() {
        let ws = buildWarnings(context: ctx(verdict: 0.03, current: 0.025, prev: 0.0))
        #expect(ws.contains { $0.title == "Impairment Has Begun" })
        #expect(!ws.contains { $0.title == "Do Not Drive" })
    }
}
