import AppIntents
import Foundation

/// What the lock-screen buttons do, installed by the app at launch.
///
/// This file is compiled into both the app and the widget extension: the widget
/// needs the intent types to draw `Button(intent:)`, and the system needs them in
/// the app to run them. A `LiveActivityIntent` always runs in the app's process
/// (iOS launches it in the background if it was killed), so these handlers are
/// only ever set and called there; the widget's copy stays nil.
@MainActor
enum LiveActivityActions {
    static var addDrink: (@MainActor (_ eventId: String, _ drinkTypeId: String) async -> Void)?
    static var addWater: (@MainActor (_ eventId: String) async -> Void)?
    static var openCamera: (@MainActor (_ eventId: String) -> Void)?
}

/// The lock-screen camera button. An intent that brings the app forward rather
/// than a `Link`: on the Lock Screen iOS does not reliably hand a Live Activity's
/// link URL to the app, so the tap opened the app but never asked for the camera.
/// The intent runs in the app's process and tells it directly.
nonisolated struct OpenNightCameraIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Take a photo" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Night") var eventId: String

    init() {}

    init(eventId: String) {
        self.eventId = eventId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveActivityActions.openCamera?(eventId)
        return .result()
    }
}

/// One tap on a lock-screen drink button logs that drink without opening the app.
nonisolated struct AddDrinkFromLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Add drink" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Drink") var drinkTypeId: String
    @Parameter(title: "Night") var eventId: String

    init() {}

    init(drinkTypeId: String, eventId: String) {
        self.drinkTypeId = drinkTypeId
        self.eventId = eventId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await LiveActivityActions.addDrink?(eventId, drinkTypeId)
        return .result()
    }
}

/// One tap on the lock-screen water button logs a glass of water.
nonisolated struct AddWaterFromLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Add water" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Night") var eventId: String

    init() {}

    init(eventId: String) {
        self.eventId = eventId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await LiveActivityActions.addWater?(eventId)
        return .result()
    }
}
