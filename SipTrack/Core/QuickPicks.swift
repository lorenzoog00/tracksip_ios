import Foundation

/// The drinks offered for one-tap logging. The drink picker's QUICK PICKS row
/// (once titled "RECENTLY ADDED") and the lock-screen / Dynamic Island buttons
/// show this same list in the same order, so a drink seen in one is the drink
/// offered by the other.
///
/// Works on ids only, so it is pure and testable without any drink catalogue.
enum QuickPicks {
    /// How many drinks the picker row and the lock screen show.
    nonisolated static let count = 3

    /// Drinks logged this night, latest log first; then the user's favourites; then
    /// their Lock Screen Drinks choice; then the catalogue in its own order fills any
    /// gap, so a fresh night still gets a full row. Each id appears once, and ids
    /// not in `catalogIds` (a deleted custom drink) are skipped.
    ///
    /// - Parameters:
    ///   - logged: every drink entry of the night, as (drink type id, log time).
    ///   - catalogIds: the drink types that exist, in catalogue order.
    nonisolated static func ids(
        logged: [(drinkTypeId: String, timestamp: Date)],
        favoriteIds: [String],
        lockScreenIds: [String],
        catalogIds: [String],
        limit: Int = count
    ) -> [String] {
        var latest: [String: Date] = [:]
        for entry in logged where latest[entry.drinkTypeId].map({ entry.timestamp > $0 }) ?? true {
            latest[entry.drinkTypeId] = entry.timestamp
        }
        // Ties (two drinks logged in the same second) break by id so the order is
        // stable between the picker and the lock screen.
        let recent = latest
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)

        let known = Set(catalogIds)
        var seen = Set<String>()
        var result: [String] = []
        for id in recent + favoriteIds + lockScreenIds + catalogIds where result.count < limit {
            if known.contains(id), seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }
}
