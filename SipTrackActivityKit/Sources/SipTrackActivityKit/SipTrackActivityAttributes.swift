import ActivityKit
import Foundation

public struct SipTrackActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        public var bac: Double
        public var drinkCount: Int
        public var stageName: String
        public var stageColorHex: String
        public var elapsedMinutes: Int
        public var eventId: String
        public var quickDrinks: [QuickDrink]
        /// Non-nil only when driving mode is on and BAC is above the limit.
        /// The widget uses this to show a live countdown via Text(timerInterval:).
        public var safeToDriveAt: Date?
        /// When BAC is projected to reach zero with no more drinks. Lets the lock
        /// screen run its own countdown between updates from the app.
        public var soberAt: Date?
        /// Night start, so the elapsed clock ticks on its own.
        public var startedAt: Date?
        /// When the app last pushed this state; shown once the state goes stale.
        public var updatedAt: Date?
        /// Glasses of water minus drinks, the same number as the in-app
        /// Hydration stat. Optional so older pushed states still decode.
        public var hydrationBalance: Int?
        /// The latest drink, so the lock screen can count up "time with drink"
        /// and fill its bar over the drinking time without any updates.
        public var currentDrinkName: String?
        public var currentDrinkSymbol: String?
        public var currentDrinkStartedAt: Date?
        public var currentDrinkMinutes: Int?
        /// A few seconds of "Red Wine added" after a lock-screen tap. Never sent
        /// to the push server, so a later push always clears it.
        public var actionText: String?

        public init(
            bac: Double,
            drinkCount: Int,
            stageName: String,
            stageColorHex: String,
            elapsedMinutes: Int,
            eventId: String,
            quickDrinks: [QuickDrink],
            safeToDriveAt: Date? = nil,
            soberAt: Date? = nil,
            startedAt: Date? = nil,
            updatedAt: Date? = nil,
            hydrationBalance: Int? = nil,
            currentDrinkName: String? = nil,
            currentDrinkSymbol: String? = nil,
            currentDrinkStartedAt: Date? = nil,
            currentDrinkMinutes: Int? = nil,
            actionText: String? = nil
        ) {
            self.bac = bac
            self.drinkCount = drinkCount
            self.stageName = stageName
            self.stageColorHex = stageColorHex
            self.elapsedMinutes = elapsedMinutes
            self.eventId = eventId
            self.quickDrinks = quickDrinks
            self.safeToDriveAt = safeToDriveAt
            self.soberAt = soberAt
            self.startedAt = startedAt
            self.updatedAt = updatedAt
            self.hydrationBalance = hydrationBalance
            self.currentDrinkName = currentDrinkName
            self.currentDrinkSymbol = currentDrinkSymbol
            self.currentDrinkStartedAt = currentDrinkStartedAt
            self.currentDrinkMinutes = currentDrinkMinutes
            self.actionText = actionText
        }
    }

    public struct QuickDrink: Codable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var symbol: String

        public init(id: String, name: String, symbol: String) {
            self.id = id
            self.name = name
            self.symbol = symbol
        }
    }

    public var eventName: String

    public init(eventName: String) {
        self.eventName = eventName
    }
}
