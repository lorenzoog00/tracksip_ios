import Foundation
import Testing
@testable import siptrack

@MainActor
struct NightStoryTests {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)
    private let types = DrinkType.presets

    @Test func photoBeforeFirstDrinkUsesZeroAndExcludedPhotosStayOut() {
        let event = night("current", hour: 0)
        let entry = drink("beer", in: event, minute: 30)
        let before = StoryAsset(id: "before", timestamp: origin.addingTimeInterval(600), isVideo: false)
        let removed = StoryAsset(id: "excluded", timestamp: origin.addingTimeInterval(2100), isVideo: false)
        var state = NightStoryState()
        state.excludedAssetIds.insert(removed.id)
        let story = NightStory(review: review(event, entries: [entry]), assets: [before, removed], state: state)
        #expect(story.moments.first?.id == "start")
        #expect(story.moments.last?.id == "end")
        #expect(story.moments.first(where: { $0.id == before.id })?.bac == 0)
        #expect(!story.moments.contains { $0.id == removed.id })
    }

    @Test func storySupportsNoPhotoAccessAndNightsWithOnlyPhotos() {
        let event = night("current", hour: 0)
        let withoutPhotos = NightStory(review: review(event, entries: [drink("beer", in: event)]),
                                       assets: [], state: NightStoryState())
        #expect(withoutPhotos.moments.map(\.id) == ["start", "peak", "end"])
        let sober = review(event, entries: [])
        let asset = StoryAsset(id: "clip", timestamp: origin.addingTimeInterval(600), isVideo: true)
        let withClip = NightStory(review: sober, assets: [asset], state: NightStoryState())
        #expect(withClip.moments.map(\.id) == ["start", "clip", "end"])
        #expect(withClip.review.timeline.isEmpty)
        #expect(NightStory(review: sober, assets: [], state: NightStoryState()).moments.isEmpty)
    }

    @Test func comparisonUsesUpToFivePreviousNightsAndTheMedian() throws {
        let current = night("current", hour: 0)
        let previous = (1...6).map { night("previous-\($0)", hour: -24 * $0) }
        let future = night("future", hour: 24)
        let counts = [1, 2, 3, 4, 25, 60]
        let entries = zip(previous, counts).map { drink($0.0.id, in: $0.0, quantity: $0.1) }
            + [drink("current", in: current, quantity: 4), drink("future", in: future, quantity: 80)]
        let comparison = try #require(review(current, entries: entries, previous: previous + [future, current]).comparison)
        #expect(comparison.count == 5)
        #expect(abs(comparison.pace / comparison.usualPace - 4.0 / 3.0) < 0.000_001)
        #expect(review(current, entries: entries, previous: Array(previous.prefix(2))).comparison == nil)
    }

    @Test func concentratedStretchUsesAlcoholDoseInsteadOfDrinkCount() throws {
        let event = night("current", hour: 0, duration: 3)
        let early = drink("early", in: event, minute: 0, quantity: 2)
        var late = drink("late", in: event, minute: 80)
        late.volumeOverrideMl = 1100
        let review = review(event, entries: [early, late])
        let window = try #require(review.strongestWindow(seconds: 3600))
        #expect(window.start == late.timestamp)
        #expect(window.grams > review.alcoholGrams / 2)
    }

    @Test func thresholdTimeInterpolatesCrossingsAndStopsAtNightEnd() {
        let points = [
            BACDataPoint(date: origin.addingTimeInterval(600), bac: 0.02),
            BACDataPoint(date: origin.addingTimeInterval(1200), bac: 0.08),
            BACDataPoint(date: origin.addingTimeInterval(1800), bac: 0.02)
        ]
        let path = BACPath(timeline: points, start: origin, end: origin.addingTimeInterval(1380))
        let context = path.above(0.05)
        #expect(path.samples.first?.bac == 0)
        #expect(path.samples.last?.date == origin.addingTimeInterval(1380))
        #expect(abs(context.seconds - 480) < 0.001)
        #expect(context.firstCrossing == origin.addingTimeInterval(900))
        #expect(context.lastReturn == nil)
    }

    @Test func videoIncludesEverySelectedPhotoAndGrowsWithTheStory() throws {
        let event = night("current", hour: 0)
        let assets = (1...48).map {
            StoryAsset(id: "photo-\($0)", timestamp: origin.addingTimeInterval(Double($0) * 120), isVideo: $0.isMultiple(of: 5))
        }
        let review = review(event, entries: [drink("beer", in: event)])
        var state = NightStoryState()
        state.excludedAssetIds.insert("photo-14")
        let story = NightStory(review: review, assets: assets, state: state)
        let selected = assets.filter { $0.id != "photo-14" }
        #expect(story.moments.compactMap(\.asset).map(\.id) == selected.map(\.id))
        #expect(story.moments.first?.id == "start")
        #expect(story.moments.last?.id == "end")
        let frames = story.videoFrameCounts(framesPerSecond: 30)
        #expect(frames.count == story.moments.count)
        #expect(frames.reduce(0, +) > 30 * 15)
        for (moment, count) in zip(story.moments, frames) where moment.asset != nil {
            #expect(count >= 60)
        }
        let shorter = NightStory(review: review, assets: Array(assets.prefix(5)), state: state)
        #expect(frames.reduce(0, +) > shorter.videoFrameCounts(framesPerSecond: 30).reduce(0, +))
        let peak = try #require(story.moments.indices.dropFirst().dropLast().max {
            story.moments[$0].bac < story.moments[$1].bac
        })
        #expect(frames[peak] == frames.max())
    }

    @Test func captionsAndExclusionsRoundTrip() throws {
        var state = NightStoryState()
        state.setCaption("  Keep\n\(String(repeating: "🍋", count: 100))", for: "photo")
        state.excludedAssetIds.insert("other")
        let saved = try JSONDecoder().decode(NightStoryState.self, from: JSONEncoder().encode(state))
        #expect(saved.captions["photo"]?.count == 90)
        #expect(saved.captions["photo"]?.hasPrefix("Keep ") == true)
        #expect(saved.excludedAssetIds == ["other"])
    }

    private func night(_ id: String, hour: Int, duration: Double = 2) -> NightEvent {
        let start = origin.addingTimeInterval(Double(hour) * 3600)
        return NightEvent(id: id, userId: "person", name: id, startTime: start, endTime: start.addingTimeInterval(duration * 3600),
                          drivingMode: false, bacLimit: nil, notes: nil, createdAt: start)
    }

    private func drink(_ id: String, in night: NightEvent, minute: Int = 0, quantity: Int = 1) -> DrinkEntry {
        DrinkEntry(id: id, eventId: night.id, drinkTypeId: "beer", timestamp: night.startTime.addingTimeInterval(Double(minute) * 60),
                   quantity: quantity, comment: nil, volumeOverrideMl: nil, abvOverride: nil)
    }

    private func review(_ event: NightEvent, entries: [DrinkEntry], previous: [NightEvent] = []) -> NightReview {
        NightReview(event: event, entries: entries, waters: [], foods: [], drinkTypes: types,
                    profile: UserProfile(), previousEvents: previous)
    }
}
