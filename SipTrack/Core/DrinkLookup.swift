import Foundation

/// One drink's physical properties, as filled in for the new-drink form.
///
/// Every field is an estimate the user can still edit before saving. Nothing
/// here is written to a night without passing through the form first: a wrong
/// pour accepted silently becomes a wrong BAC on a screen someone may decide
/// whether to drive on.
struct DrinkLookupResult: Equatable {
    var name: String
    var volumeMl: Double
    var abv: Double
    var calories: Double
    var minutes: Int
    var category: String
    /// Servings the text asked for. The form creates a drink, it does not log
    /// one, so this is shown as a hint rather than acted on.
    var quantity: Int
}

enum DrinkLookupError: LocalizedError, Equatable {
    case tooShort
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .tooShort: return "Describe the drink in a few words."
        case .malformedResponse: return "Could not read that drink. Please try again."
        }
    }
}

enum DrinkLookup {
    static let categories = ["beer", "wine", "spirits", "agave", "cocktails"]

    /// Suggestions offered under the description field.
    ///
    /// Every one of these must be a drink the catalog does NOT already have:
    /// an example that `localMatch` answers from the presets teaches the user
    /// that the feature only repeats what they could have tapped, which is the
    /// opposite of the point. `DrinkLookupTests` asserts that.
    /// Paloma, carajillo and cuba libre were here until they became presets;
    /// `noSuggestedExampleIsAlreadyInTheCatalog` is what caught it.
    static let examples = ["aperol spritz", "negroni", "clericot", "espresso martini"]

    /// Mirrors the server's bounds. A response that clears the server and
    /// fails here means the two have drifted apart, which is worth failing on
    /// rather than papering over.
    private static let volumeRange = 5.0...2000.0
    private static let abvRange = 0.0...96.0
    private static let caloriesRange = 0.0...2000.0
    private static let minutesRange = 1...240
    private static let quantityRange = 1...20

    // MARK: - Query

    /// Trim and collapse a query the way the server will, so the client
    /// rejects what the server would reject without spending a call on it.
    static func normalizedQuery(_ raw: String) throws -> String {
        let query = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard query.count >= 2, query.count <= 120 else { throw DrinkLookupError.tooShort }
        return query
    }

    // MARK: - Local catalog

    /// A drink the user already has that the query plainly names.
    ///
    /// This is checked before the network: the common case is a second mezcal,
    /// and spending one of five monthly lookups on a drink already in the
    /// catalog would be the worst possible use of the allowance.
    static func localMatch(for query: String, in catalog: [DrinkType]) -> DrinkType? {
        let needle = fold(stripLeadingCount(query))
        guard needle.count >= 2 else { return nil }
        let candidates = catalog.map { (drink: $0, name: fold($0.name)) }
            .filter { !$0.name.isEmpty }
        if let exact = candidates.first(where: { $0.name == needle }) {
            return exact.drink
        }
        // A containment match has to be the longer name containing the whole
        // shorter one, so "gin" does not match "ginger beer" on a prefix.
        let contained = candidates.filter {
            $0.name.contains(needle) || needle.contains($0.name)
        }
        // Several equally good matches is not a match: prefilling the wrong
        // one of them is worse than asking the model.
        guard contained.count == 1 else { return nil }
        return contained[0].drink
    }

    /// Prefill values taken from a drink the user already has.
    static func result(from drink: DrinkType, quantity: Int) -> DrinkLookupResult {
        DrinkLookupResult(
            name: drink.name,
            volumeMl: drink.defaultVolumeMl,
            abv: drink.defaultAbv,
            calories: drink.caloriesPerServing,
            minutes: drink.effectiveDrinkingMinutes,
            category: drink.drinkCategory,
            quantity: quantity
        )
    }

    /// Servings named at the start of the query, for the local path. The
    /// server reads the whole phrase; this only has to catch "2 mezcales".
    static func leadingCount(in query: String) -> Int {
        let first = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first ?? ""
        guard let value = Int(first), quantityRange.contains(value) else { return 1 }
        return value
    }

    // MARK: - Server response

    /// Decode the callable's payload, re-checking every bound the server
    /// checked.
    static func parse(_ payload: [String: Any]) throws -> (result: DrinkLookupResult, remaining: Int?) {
        guard let drink = payload["drink"] as? [String: Any],
              let name = (drink["name"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, name.count <= 60,
              let category = drink["category"] as? String,
              categories.contains(category),
              let volumeMl = number(drink["volumeMl"]), volumeRange.contains(volumeMl),
              let abv = number(drink["abv"]), abvRange.contains(abv),
              let calories = number(drink["calories"]), caloriesRange.contains(calories),
              let minutes = integer(drink["minutes"]), minutesRange.contains(minutes),
              let quantity = integer(drink["quantity"]), quantityRange.contains(quantity)
        else { throw DrinkLookupError.malformedResponse }
        let result = DrinkLookupResult(
            name: name, volumeMl: volumeMl, abv: abv, calories: calories,
            minutes: minutes, category: category, quantity: quantity
        )
        return (result, integer(payload["remaining"]))
    }

    // MARK: - Presentation

    /// The form's own icon for a category, so a looked-up drink lands on a
    /// sensible symbol instead of the generic cup.
    static func sfSymbol(for category: String) -> String {
        switch category {
        case "beer": return "mug.fill"
        case "wine": return "wineglass.fill"
        case "spirits": return "flask"
        case "agave": return "flask.fill"
        default: return "cup.and.saucer.fill"
        }
    }

    // MARK: - Helpers

    private static func number(_ value: Any?) -> Double? {
        // The callable envelope is JSON, so whole numbers arrive as Int and
        // the rest as Double. Both are valid here.
        if let double = value as? Double { return double.isFinite ? double : nil }
        if let int = value as? Int { return Double(int) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double, double.isFinite, double == double.rounded() {
            return Int(double)
        }
        return nil
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingCount(_ query: String) -> String {
        let parts = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard parts.count > 1, Int(parts[0]) != nil else { return query }
        return parts.dropFirst().joined(separator: " ")
    }
}
