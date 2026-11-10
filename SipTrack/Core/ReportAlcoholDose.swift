import Foundation

struct ReportAlcoholDose {
    static let reportHeading = "ALCOHOL LOGGED:"

    private struct Pour: Hashable {
        let typeId: String
        let name: String
        let volumeMl: Double
        let abv: Double

        func fields(quantity: Int, grams: Double) -> [String: Any] {
            ["name": name, "quantity": quantity, "volumeMlPerServing": volumeMl, "abv": abv,
             "grams": grams, "standardDrinks": BACCalculator.standardDrinks(alcoholGrams: grams)]
        }
    }

    private struct Log {
        let pour: Pour
        let quantity: Int
        let grams: Double
        let timestamp: Date
    }

    private let logs: [Log]
    let loggedServings: Int
    let missingServings: Int
    let grams: Double
    var standardDrinks: Double { BACCalculator.standardDrinks(alcoholGrams: grams) }

    init(entries: [DrinkEntry], drinkTypes: [DrinkType]) {
        let catalog = Dictionary(drinkTypes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var logs: [Log] = []
        var loggedServings = 0
        var missingServings = 0
        for entry in entries where entry.quantity > 0 {
            loggedServings += entry.quantity
            let type = catalog[entry.drinkTypeId]
            guard let volume = entry.volumeOverrideMl ?? type?.defaultVolumeMl, volume.isFinite, volume > 0,
                  let abv = entry.abvOverride ?? type?.defaultAbv, abv.isFinite, (0...100).contains(abv) else {
                missingServings += entry.quantity
                continue
            }
            let amount = BACCalculator.calculateAlcohol(volumeMl: volume, abv: abv, quantity: entry.quantity)
            guard amount.isFinite else {
                missingServings += entry.quantity
                continue
            }
            let name = String((type?.name ?? "Unknown drink").split(whereSeparator: \.isWhitespace)
                .joined(separator: " ").prefix(64))
            let pour = Pour(typeId: entry.drinkTypeId, name: name.isEmpty ? "Unnamed drink" : name, volumeMl: volume, abv: abv)
            logs.append(Log(pour: pour, quantity: entry.quantity, grams: amount, timestamp: entry.timestamp))
        }
        self.logs = logs
        self.loggedServings = loggedServings
        self.missingServings = missingServings
        self.grams = logs.reduce(0) { $0 + $1.grams }
    }

    func grams(upTo time: Date) -> Double {
        logs.filter { $0.timestamp <= time }.reduce(0) { $0 + $1.grams }
    }

    func fields(start: Date? = nil, end: Date? = nil) -> [String: Any] {
        let groups = Dictionary(grouping: logs, by: \.pour).map { pour, entries in
            (pour: pour, quantity: entries.reduce(0) { $0 + $1.quantity }, grams: entries.reduce(0) { $0 + $1.grams })
        }.sorted {
            if $0.grams != $1.grams { return $0.grams > $1.grams }
            return $0.pour.name < $1.pour.name
        }
        let other = groups.dropFirst(6)
        var dose: [String: Any] = [
            "grams": grams, "standardDrinks": standardDrinks,
            "loggedServings": loggedServings, "missingServings": missingServings,
            "otherGroups": other.count, "otherGrams": other.reduce(0) { $0 + $1.grams },
        ]
        if let largest = logs.max(by: { $0.grams < $1.grams }), largest.grams > 0 {
            dose["largestEntry"] = largest.pour.fields(quantity: largest.quantity, grams: largest.grams)
        }
        if let start, let end {
            let duration = end.timeIntervalSince(start)
            if duration >= 60 { dose["standardDrinksPerHour"] = standardDrinks * 3600 / duration }
            if let strongest = strongestHour() {
                dose["strongestHourStandardDrinks"] = BACCalculator.standardDrinks(alcoholGrams: strongest.grams)
                dose["strongestHourStartMinute"] = Int(strongest.time.timeIntervalSince(start) / 60)
            }
        }
        return ["alcoholDose": dose, "drinks": groups.prefix(6).map {
            $0.pour.fields(quantity: $0.quantity, grams: $0.grams)
        }]
    }

    private func strongestHour() -> (time: Date, grams: Double)? {
        let sorted = logs.filter { $0.grams > 0 }.sorted { $0.timestamp < $1.timestamp }
        var right = 0
        var grams = 0.0
        var best: (time: Date, grams: Double)?
        for left in sorted.indices {
            let start = sorted[left].timestamp
            while right < sorted.count, sorted[right].timestamp.timeIntervalSince(start) < 3600 {
                grams += sorted[right].grams
                right += 1
            }
            if grams > (best?.grams ?? 0) { best = (start, grams) }
            grams -= sorted[left].grams
        }
        return best
    }
}
