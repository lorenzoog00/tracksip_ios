import CoreHaptics
import Foundation
import UIKit

// The CoreHaptics shell: owns the engine and turns a `HapticPattern` into actual
// events. Every rule that can be decided without hardware lives in `HapticSpec`,
// so this file only wraps the framework — it knows nothing about drinks, BAC or
// views, and nothing here ever throws out to a call site.
@MainActor
final class Haptics {

    static let shared = Haptics()

    // MARK: - Pattern tuning
    //
    // Intensity is "how hard", sharpness is "how crisp", and the two are set
    // independently per pattern. The invariant to preserve when retuning any of
    // these: `storyAdvanceIntensity` stays well below `ceilingIntensity`, and
    // `ceilingCrossed` is the only pattern that pairs full intensity with a
    // doubled transient — that pairing is what keeps the alarm unmistakable even
    // when a story tap's sharpness reaches the alarm's 0.9. `init` asserts the
    // ordering. (`peak` also reaches full intensity, but it is a single 0.25 s
    // swell; `warning` sits at 0.70 with a deliberately duller, slower shape.)

    private static let selectionIntensity: Float = 0.30
    private static let selectionSharpness: Float = 0.70

    private static let lightIntensity: Float = 0.45
    private static let lightSharpness: Float = 0.35

    private static let successFirstIntensity: Float = 0.45
    private static let successFirstSharpness: Float = 0.40
    private static let successSecondIntensity: Float = 0.75
    private static let successSecondSharpness: Float = 0.60
    private static let successGap: TimeInterval = 0.10

    private static let warningIntensity: Float = 0.70
    private static let warningSharpness: Float = 0.30
    private static let warningGap: TimeInterval = 0.20

    // Every story-card tap lands at this strength, whatever the BAC delta: the
    // character of the tap is carried entirely by `HapticSpec.advanceSharpness`,
    // which can reach 0.9 — the same sharpness as the ceiling alarm. Holding the
    // intensity here well under the alarm's 1.0 is what keeps the two apart, so
    // this constant must stay low: the app does not get louder as the night gets
    // worse.
    private static let storyAdvanceIntensity: Float = 0.35

    private static let ceilingIntensity: Float = 1.0
    private static let ceilingSharpness: Float = 0.90
    private static let ceilingGap: TimeInterval = 0.12

    // The event-level intensity for any pattern whose strength is shaped by a
    // dynamic parameter or a curve. An intensity *control* multiplies the event's
    // own intensity, so the event has to run at full scale for the control's value
    // to be the one that is actually felt. This is not a tuning knob: lowering it
    // silently scales `peak`'s ramp and every continuous update down with it.
    private static let fullScaleIntensity: Float = 1.0

    private static let peakDuration: TimeInterval = 0.25
    private static let peakSharpness: Float = 0.50
    private static let peakStartIntensity: Float = 0.30
    private static let peakEndIntensity: Float = 1.0

    // The confirmation tap for a logged drink — named for the pour it once closed,
    // but `AppState.addDrink` plays it now, so it follows the add rather than the
    // gesture. Crisp and middling-strong: it has to read as "that landed" through
    // a pocket, without competing with the ceiling alarm.
    private static let pourEndIntensity: Float = 0.60
    private static let pourEndSharpness: Float = 0.90

    private static let continuousSharpness: Float = 0.50
    // CoreHaptics caps a continuous event at 30 s; a held pour never runs this
    // long, and if one did the buzz would simply end while the pour carried on.
    private static let continuousDuration: TimeInterval = 20

    // MARK: - State

    // Hardware support cannot change while the process lives, so it is read once.
    private let supportsHaptics: Bool

    // The user's `hapticsEnabled` preference, cached. `DataStore.loadUserProfile()`
    // reads a JSON file off disk and decodes it, which has no business running on
    // the main thread for every tap in the drink picker, so it is read here at
    // first use, re-read in `prepare()`, and otherwise pushed in by whoever
    // changes it (`setEnabled`). Never read on the tap path.
    private var isEnabled: Bool

    private var engine: CHHapticEngine?
    private var isEngineRunning = false
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?

    private init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        isEnabled = DataStore.shared.loadUserProfile().hapticsEnabled
        // The one tuning rule that needs no hardware to check, and that no test
        // can reach: a story tap must stay clearly weaker than the ceiling alarm.
        assert(Self.storyAdvanceIntensity < Self.ceilingIntensity)
    }

    // MARK: - Lifecycle

    // Re-reads the preference and applies it: with haptics on this brings the
    // engine up, so the first tap of a gesture is not the one that pays for
    // `start()`; with haptics off it *releases* the engine instead, since this is
    // also the path that discovers a preference changed somewhere this type was
    // not told about (another device via sync, a reset profile). Idempotent —
    // meant to be called on scene activation and on view appearance, before a
    // gesture rather than during it.
    func prepare() {
        isEnabled = DataStore.shared.loadUserProfile().hapticsEnabled
        applyPreference()
    }

    // The push path, for the caller that has just changed the preference: it hands
    // the value straight over instead of leaving this type to rediscover it from
    // disk at some later `prepare()`. Switching haptics off takes effect here and
    // now, which is the only behaviour an opt-out may have.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        applyPreference()
    }

    // Brings the engine up or gives it back, per the current preference. Haptics
    // off releases the hardware immediately rather than idling on it: the engine
    // does not auto-shut-down, and this also ends a pour buzz that was running
    // when the user flipped the switch.
    private func applyPreference() {
        guard HapticSpec.shouldPlay(enabled: isEnabled, supportsHaptics: supportsHaptics) else {
            stop()
            return
        }
        _ = runningEngine()
    }

    // Gives up the haptic hardware. Two callers, with the same meaning — "stop
    // holding the hardware" — and different reasons: the app leaving the
    // foreground, and `applyPreference` finding haptics switched off, which is the
    // opt-out release path. The engine object survives either way; the next `play`
    // starts it again if the preference allows, so this is not a kill switch.
    func stop() {
        stopContinuousPlayer()
        engine?.stop(completionHandler: nil)
        isEngineRunning = false
    }

    // MARK: - Transient patterns

    func play(_ pattern: HapticPattern) {
        // The user switched haptics off: nothing plays, whatever the hardware.
        // This is the app's own reduce-haptics switch, so falling back to a
        // UIFeedbackGenerator here would buzz someone who opted out.
        guard isEnabled else { return }

        // Enabled, but this device cannot render custom patterns (an iPad or the
        // Simulator, given the iOS 18 floor). The named system gestures still have
        // UIKit equivalents; the shaped ones do not and stay silent.
        guard HapticSpec.shouldPlay(enabled: isEnabled, supportsHaptics: supportsHaptics) else {
            playFallback(pattern)
            return
        }

        guard let engine = runningEngine() else { return }
        do {
            let shape = try makePattern(for: pattern)
            let player = try engine.makePlayer(with: shape)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Most likely the engine died between our last check and now, so drop
            // the running flag and let the next call start it again.
            isEngineRunning = false
            log("play failed: \(error)")
        }
    }

    // MARK: - Continuous pattern

    // Starts the single continuous buzz used while a pour is held. `intensity` is
    // sent as a dynamic parameter rather than baked into the event so that
    // `updateContinuous` can replace it without compounding.
    func beginContinuous(initialIntensity: Float) {
        guard isEnabled,
              HapticSpec.shouldPlay(enabled: isEnabled, supportsHaptics: supportsHaptics) else { return }

        stopContinuousPlayer()
        guard let engine = runningEngine() else { return }
        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    // Full-scale event: the intensity *control* below does the
                    // shaping, and it multiplies this value.
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Self.fullScaleIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Self.continuousSharpness)
                ],
                relativeTime: 0,
                duration: Self.continuousDuration
            )
            let start = CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: clamped(initialIntensity),
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [start])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            continuousPlayer = player
        } catch {
            continuousPlayer = nil
            isEngineRunning = false
            log("beginContinuous failed: \(error)")
        }
    }

    func updateContinuous(intensity: Float) {
        guard let player = continuousPlayer else { return }
        let parameter = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: clamped(intensity),
            relativeTime: 0
        )
        do {
            try player.sendParameters([parameter], atTime: CHHapticTimeImmediate)
        } catch {
            log("updateContinuous failed: \(error)")
        }
    }

    // Ends the buzz, and nothing else. It deliberately plays no closing tap: the
    // buzz also ends when the grid takes the touch to scroll, and no drink is
    // added then, so the confirmation tap belongs to `AppState.addDrink` instead.
    // Needs no gate of its own — with haptics off there is no player to stop.
    func endContinuous() {
        stopContinuousPlayer()
    }

    // MARK: - Engine

    // The engine, started. Creates it on first use and restarts it after a
    // `stop()`, an audio-session interruption or a reset, so a phone call
    // mid-night does not kill haptics for the rest of it.
    private func runningEngine() -> CHHapticEngine? {
        if engine == nil { makeEngine() }
        guard let engine else { return nil }
        guard !isEngineRunning else { return engine }
        // Never start while backgrounded: the old UIKit calls were silent no-ops
        // there, and a Watch or deep-link add or a profile write must not poke the
        // hardware. Asked of the OS at the point of use, not tracked in a flag that
        // prepare()/stop() would have to keep in step. `.inactive` (launch, mid-
        // transition) still starts.
        guard UIApplication.shared.applicationState != .background else { return nil }
        do {
            try engine.start()
            isEngineRunning = true
            return engine
        } catch {
            isEngineRunning = false
            log("engine start failed: \(error)")
            return nil
        }
    }

    private func makeEngine() {
        let created: CHHapticEngine
        do {
            created = try CHHapticEngine()
        } catch {
            log("engine init failed: \(error)")
            return
        }
        // Haptics only: the engine then leaves the audio session alone, so it
        // neither interrupts whatever is playing nor rides on its interruptions.
        created.playsHapticsOnly = true

        // Both handlers arrive on an arbitrary queue, hence the explicit hop. They
        // only mark the engine dead; the restart happens lazily on the next call,
        // and any player built against the old engine is invalid, so it is dropped.
        let stopped: @Sendable (CHHapticEngine.StoppedReason) -> Void = { [weak self] reason in
            Task { @MainActor in self?.engineDidDie("stopped (reason \(reason.rawValue))") }
        }
        let reset: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.engineDidDie("reset") }
        }
        created.stoppedHandler = stopped
        created.resetHandler = reset

        engine = created
        isEngineRunning = false
    }

    private func engineDidDie(_ cause: String) {
        isEngineRunning = false
        continuousPlayer = nil
        log("engine \(cause); will restart on next play")
    }

    private func stopContinuousPlayer() {
        guard let player = continuousPlayer else { return }
        continuousPlayer = nil
        do {
            try player.stop(atTime: CHHapticTimeImmediate)
        } catch {
            log("continuous stop failed: \(error)")
        }
    }

    // MARK: - Pattern shapes

    private func makePattern(for pattern: HapticPattern) throws -> CHHapticPattern {
        switch pattern {
        case .selection:
            return try CHHapticPattern(
                events: [transient(intensity: Self.selectionIntensity, sharpness: Self.selectionSharpness)],
                parameters: []
            )

        case .light:
            return try CHHapticPattern(
                events: [transient(intensity: Self.lightIntensity, sharpness: Self.lightSharpness)],
                parameters: []
            )

        // A rising pair, and the one `exportDone` borrows.
        case .success, .exportDone:
            return try CHHapticPattern(
                events: [
                    transient(intensity: Self.successFirstIntensity, sharpness: Self.successFirstSharpness),
                    transient(
                        intensity: Self.successSecondIntensity,
                        sharpness: Self.successSecondSharpness,
                        at: Self.successGap
                    )
                ],
                parameters: []
            )

        // Two dull, slow taps — deliberately unlike the ceiling alarm's two sharp
        // ones.
        case .warning:
            return try CHHapticPattern(
                events: [
                    transient(intensity: Self.warningIntensity, sharpness: Self.warningSharpness),
                    transient(
                        intensity: Self.warningIntensity,
                        sharpness: Self.warningSharpness,
                        at: Self.warningGap
                    )
                ],
                parameters: []
            )

        // One tap, always the same strength; `HapticSpec.advanceSharpness` returns
        // 0.2...0.9, so the value needs no clamping here.
        case .storyAdvance(let bacDelta):
            return try CHHapticPattern(
                events: [
                    transient(
                        intensity: Self.storyAdvanceIntensity,
                        sharpness: HapticSpec.advanceSharpness(bacDelta: bacDelta)
                    )
                ],
                parameters: []
            )

        case .ceilingCrossed:
            return try CHHapticPattern(
                events: [
                    transient(intensity: Self.ceilingIntensity, sharpness: Self.ceilingSharpness),
                    transient(
                        intensity: Self.ceilingIntensity,
                        sharpness: Self.ceilingSharpness,
                        at: Self.ceilingGap
                    )
                ],
                parameters: []
            )

        // A short swell: the curve scales the event's intensity, so the event runs
        // at full scale and the curve carries the 0.3 → 1.0 ramp.
        case .peak:
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Self.fullScaleIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Self.peakSharpness)
                ],
                relativeTime: 0,
                duration: Self.peakDuration
            )
            let ramp = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: Self.peakStartIntensity),
                    CHHapticParameterCurve.ControlPoint(
                        relativeTime: Self.peakDuration,
                        value: Self.peakEndIntensity
                    )
                ],
                relativeTime: 0
            )
            return try CHHapticPattern(events: [event], parameterCurves: [ramp])

        // One crisp tap confirming a logged drink, on every path that logs one.
        case .pourEnd:
            return try CHHapticPattern(
                events: [transient(intensity: Self.pourEndIntensity, sharpness: Self.pourEndSharpness)],
                parameters: []
            )
        }
    }

    private func transient(intensity: Float, sharpness: Float, at relativeTime: TimeInterval = 0) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: relativeTime
        )
    }

    // MARK: - UIKit fallback

    // Only for hardware that cannot render custom patterns. The genuinely shaped
    // patterns (story, ceiling, peak) carry their meaning in a curve or a timed
    // pair that UIKit has no equivalent for, so they stay silent. `.pourEnd` is a
    // single transient, which `.light` does approximate — and since it is the
    // confirmation tap for every logged drink, leaving it as the one dead entry
    // would silence the app's most frequent haptic while this table read as if it
    // were complete.
    // No device in range actually takes this path (the iOS 18 floor means A12 or
    // newer, all of which report `supportsHaptics`, and iPad has no Taptic Engine
    // so the generators were no-ops there anyway), but the table should be true.
    private func playFallback(_ pattern: HapticPattern) {
        switch pattern {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .light, .pourEnd:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success, .exportDone:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .storyAdvance, .ceilingCrossed, .peak:
            break
        }
    }

    // MARK: - Helpers

    // CoreHaptics parameters live in 0...1 and reject anything else, so values
    // that arrive from a caller are pinned to the range. Not a rule — just the
    // framework's own bounds.
    private func clamped(_ value: Float) -> Float {
        guard !value.isNaN else { return 0 }
        return min(max(value, 0), 1)
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[Haptics] \(message)")
        #endif
    }
}
