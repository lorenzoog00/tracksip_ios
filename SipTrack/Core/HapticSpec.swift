import Foundation

// The named gestures SipTrack can play. Pure data: the CoreHaptics engine
// (`Haptics`) maps each case onto actual events, so every decision that can be
// made without hardware lives in `HapticSpec` below and stays unit-testable.
enum HapticPattern {
    case selection
    case light
    case success
    case warning
    // One tap per Night Story card; `bacDelta` is the BAC change since the
    // previous card and sets how hard the tap lands (see `advanceIntensity`).
    case storyAdvance(bacDelta: Double)
    case ceilingCrossed
    case peak
    case pourEnd
    case exportDone
}

// The hardware-independent half of the haptics feature. CHHapticEngine needs a
// real device and reports unsupported on the Simulator, so the engine stays a
// thin shell and the rules it applies are kept here: Foundation only, no
// CoreHaptics / UIKit / SwiftUI.
enum HapticSpec {

    // Intensity range for a story-card tap, and the |BAC delta| at which it
    // saturates: a swing of 0.04 or more is as hard as the tap gets.
    private static let minAdvanceIntensity = 0.2
    private static let maxAdvanceIntensity = 0.9
    private static let saturatingBACDelta = 0.04

    // Custom haptics play only when the user has them on AND the hardware can
    // render them. When this is false the engine falls back to the plain
    // UIFeedbackGenerators (or stays silent) rather than playing nothing at all.
    static func shouldPlay(enabled: Bool, supportsHaptics: Bool) -> Bool {
        enabled && supportsHaptics
    }

    // Tap strength for a story card, 0.2...0.9. Scales linearly with the
    // magnitude of the BAC change since the previous card and clamps at 0.04, so
    // a flat stretch of the night still gets a gentle tap and a big swing never
    // exceeds 0.9. Direction is ignored: dropping 0.02 is as notable as rising
    // 0.02. A NaN delta is treated as no change so the result is always in range.
    static func advanceIntensity(bacDelta: Double) -> Float {
        guard !bacDelta.isNaN else { return Float(minAdvanceIntensity) }
        let fraction = min(abs(bacDelta) / saturatingBACDelta, 1.0)
        return Float(minAdvanceIntensity * (1 - fraction) + maxAdvanceIntensity * fraction)
    }

    // Whether this BAC tick should play the "you passed your ceiling" haptic.
    // A strict upward edge, at most once per night:
    //   - needs a ceiling (nil means the user never set one);
    //   - `previousBAC < ceiling && currentBAC >= ceiling`, so staying above it,
    //     or the first tick after a cold launch where previous == current, is
    //     silent;
    //   - `alreadyFired` latches for the rest of the night, so dipping back
    //     under and crossing again does not buzz twice.
    static func crossingFires(previousBAC: Double, currentBAC: Double, ceiling: Double?, alreadyFired: Bool) -> Bool {
        guard let ceiling, !alreadyFired else { return false }
        return previousBAC < ceiling && currentBAC >= ceiling
    }
}
