import Foundation

struct StoryMoment: Identifiable {
    enum Kind { case start, media(StoryAsset), peak, end }

    let kind: Kind
    let timestamp: Date
    let bac: Double

    var id: String {
        switch kind {
        case .start: "start"
        case .media(let asset): asset.id
        case .peak: "peak"
        case .end: "end"
        }
    }

    var asset: StoryAsset? {
        if case .media(let asset) = kind { return asset }
        return nil
    }
}

struct NightStory {
    let review: NightReview
    let moments: [StoryMoment]
    let suggestions: [String: String]

    init(review: NightReview, assets: [StoryAsset], state: NightStoryState) {
        self.review = review
        let start = review.event.startTime
        let end = review.end
        let selected = assets.filter { !state.excludedAssetIds.contains($0.id) && $0.timestamp >= start && $0.timestamp <= end }
        guard !selected.isEmpty || review.drinkCount > 0 else {
            moments = []
            suggestions = [:]
            return
        }
        let sessionPeak = review.path.samples.filter { $0.bac > 0 }.max { $0.bac < $1.bac }
        var middle = selected.map { StoryMoment(kind: .media($0), timestamp: $0.timestamp, bac: review.bac(at: $0.timestamp)) }
        if let peak = sessionPeak, !selected.contains(where: { abs($0.timestamp.timeIntervalSince(peak.date)) <= 600 }) {
            middle.append(StoryMoment(kind: .peak, timestamp: peak.date, bac: peak.bac))
        }
        let moments = [StoryMoment(kind: .start, timestamp: start, bac: review.bac(at: start))]
            + middle.sorted { $0.timestamp < $1.timestamp }
            + [StoryMoment(kind: .end, timestamp: end, bac: review.bac(at: end))]
        self.moments = moments

        var facts: [String: String] = [:]
        func add(_ text: String, at date: Date) {
            guard let nearest = moments.filter({ facts[$0.id] == nil }).min(by: {
                abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
            }) else { return }
            facts[nearest.id] = text
        }
        if let limit = review.ceiling.line, let crossed = review.path.above(limit).firstCrossing {
            add("The estimated BAC crossed the \(review.ceiling.name.lowercased()) at \(NightReview.time(crossed)).",
                at: crossed)
        }
        if let peak = sessionPeak {
            add(String(format: "Estimated peak during the night: %.3f%% at %@.", peak.bac, NightReview.time(peak.date)),
                at: peak.date)
        }
        if let stretch = review.strongestWindow(seconds: 1800) {
            let drinks = BACCalculator.standardDrinks(alcoholGrams: stretch.grams)
            add(String(format: "%.1f standard drinks logged in your busiest 30 minutes.", drinks), at: stretch.start)
        }
        if let peak = sessionPeak, let limit = review.ceiling.line, peak.bac >= 2 * limit {
            add(String(format: "The estimated peak was %.1f× the %@.", peak.bac / limit,
                       review.ceiling.name.lowercased()), at: peak.date)
        }
        if let comparison = review.comparison {
            add(String(format: "%.1f standard drinks per hour, compared with %.1f on recent nights.",
                       comparison.pace, comparison.usualPace), at: end)
        }
        if let water = review.waters.first {
            add("Water logged at \(NightReview.time(water.timestamp)).", at: water.timestamp)
        }
        if let limit = review.ceiling.line, let returned = review.path.above(limit).lastReturn {
            add("The estimate fell below the \(review.ceiling.name.lowercased()) at \(NightReview.time(returned)).", at: returned)
        }
        if let lastPositive = review.timeline.lastIndex(where: { $0.bac > 0 }),
           let zero = review.timeline.dropFirst(lastPositive + 1).first(where: { $0.bac == 0 }), zero.date > end {
            add("Projected to reach 0.000% at \(NightReview.time(zero.date)), assuming no more drinks.", at: end)
        }
        suggestions = facts
    }

    func videoFrameCounts(framesPerSecond: Int) -> [Int] {
        guard framesPerSecond > 0 else { return [] }
        let peakId = moments.filter { $0.id != "start" && $0.id != "end" && $0.bac > 0 }.max { $0.bac < $1.bac }?.id
        return moments.map { moment in
            let seconds: Double
            switch moment.id {
            case "start": seconds = 2.4
            case "end": seconds = 2.2
            default: seconds = moment.id == peakId ? 2.9 : 2
            }
            return Int((seconds * Double(framesPerSecond)).rounded())
        }
    }
}
