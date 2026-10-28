import Foundation

// The named gestures SipTrack can play. Pure data: the CoreHaptics engine
// (`Haptics`) maps each case onto actual events, so every decision that can be
// made without hardware lives in `HapticSpec` below and stays unit-testable.
enum HapticPattern {
    case selection
    case light
    case success
    case warning
    // One tap per Night Story card. `bacDelta` is the BAC change since the
    // previous card and sets how crisp the tap feels (see `advanceSharpness`);
    // every story tap lands at the same strength.
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

    // Sharpness range for a story-card tap, and the |BAC delta| at which it
    // saturates: a swing of 0.04 or more is as crisp as the tap gets.
    private static let minAdvanceSharpness = 0.2
    private static let maxAdvanceSharpness = 0.9
    private static let saturatingBACDelta = 0.04

    // The gate for the CoreHaptics engine: true only when the user has haptics
    // switched on in the app AND the hardware can render them.
    static func shouldPlay(enabled: Bool, supportsHaptics: Bool) -> Bool {
        enabled && supportsHaptics
    }

    // CoreHaptics sharpness for a story-card tap, 0.2...0.9 (low is dull and
    // round, high is crisp). Grows linearly with the magnitude of the BAC change
    // since the previous card and saturates at 0.04, so a flat stretch of the
    // night gets a dull tap and a big swing a crisp one. Only sharpness varies:
    // intensity is the same for every tap, so the app does not get louder as the
    // night gets worse. Direction is ignored: dropping 0.02 is as notable as
    // rising 0.02. A NaN delta is treated as no change so the result is always
    // in range (Swift's `min` would otherwise pass NaN straight through).
    static func advanceSharpness(bacDelta: Double) -> Float {
        guard !bacDelta.isNaN else { return Float(minAdvanceSharpness) }
        let fraction = min(abs(bacDelta) / saturatingBACDelta, 1.0)
        return Float(minAdvanceSharpness * (1 - fraction) + maxAdvanceSharpness * fraction)
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

    // Whether a drag on the ceiling slider should tick: only when the value it
    // lands on differs from the one before. nil is the "off" state, so switching
    // on and off both tick, and nothing else in the UI confirms the off one. A touch
    // on the notch already selected, or a drag past the clamped ends, is not a
    // change and stays silent. Plain equality is exact here: the slider only ever
    // produces k * 0.005 from one multiply, so the same notch is the same Double.
    static func selectionChanged(from: Double?, to: Double?) -> Bool {
        from != to
    }
}
