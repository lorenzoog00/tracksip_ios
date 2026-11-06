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
            updatedAt: Date? = nil
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
