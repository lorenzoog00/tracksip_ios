import Foundation
import Testing
@testable import siptrack

struct NightBACChartTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test func historyAndProjectionMeetAtTheLiveEstimate() {
        let now = date(minutes: 10)
        let data = chart(now: now, currentBAC: 0.02, samples: [
            BACDataPoint(date: date(minutes: 5), bac: 0.01),
            BACDataPoint(date: now, bac: 0.03),
            BACDataPoint(date: date(minutes: 20), bac: 0.04)
        ])
        #expect(data.history.map(\.date) == [start, date(minutes: 5), now])
        #expect(data.history.last?.bac == 0.02)
        #expect(data.projection.map(\.date) == [now, date(minutes: 20)])
        #expect(data.projection.first?.bac == 0.02)
        #expect(abs(data.bac(at: date(minutes: 15)) - 0.03) < 0.000_001)
        #expect(data.bac(at: start) == 0)
    }

    @Test func zeroBACHasAVisibleFlatProjection() {
        let now = date(minutes: 5)
        let data = chart(now: now)
        #expect(data.history.count == 2)
        #expect(data.projection.map(\.bac) == [0, 0])
        #expect(data.end == date(minutes: 65))
    }

    @Test func hourlyLogGroupsQuantitiesAndKeepsFutureDrinksOut() {
        let data = chart(now: date(minutes: 65), entries: [
            drink("a", type: "beer", minute: 5, quantity: 2),
            drink("b", type: "beer", minute: 15),
            drink("c", type: "tequila", minute: 40),
            drink("d", type: "beer", minute: 60),
            drink("e", type: "beer", minute: 70, quantity: 5)
        ])
        #expect(data.hours.map(\.start) == [start, date(minutes: 60)])
        #expect(data.hour(containing: date(minutes: 59))?.summary == "Beer ×3 · Tequila ×1")
        #expect(data.hour(containing: date(minutes: 60))?.summary == "Beer ×1")
        #expect(data.hour(containing: date(minutes: 120)) == nil)
    }

    private func chart(
        now: Date, currentBAC: Double = 0, samples: [BACDataPoint] = [], entries: [DrinkEntry] = []
    ) -> NightBACChartData {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return NightBACChartData(
            eventStart: start, now: now, currentBAC: currentBAC, samples: samples,
            entries: entries, drinkTypes: DrinkType.presets, calendar: calendar
        )
    }

    @Test func axisStrideWidensWithTheSpanSoHourLabelsCannotCollide() {
        let hours = { (h: Double) in NightBACChartData.xStrideHours(span: h * 3600) }
        #expect(hours(0) == 1)
        #expect(hours(2) == 1)
        #expect(hours(3.9) == 1)
        #expect(hours(4) == 2)
        #expect(hours(7.9) == 2)
        #expect(hours(8) == 3)
        #expect(hours(13.9) == 3)
        #expect(hours(14) == 4)
        #expect(hours(30) == 4)
    }

    @Test func anEightHourNightLabelsAtMostFourHours() {
        let now = date(minutes: 8 * 60)
        let data = chart(now: now, currentBAC: 0, samples: [BACDataPoint(date: now, bac: 0)])
        let span = data.end.timeIntervalSince(data.start)
        #expect(span / 3600 / Double(data.xStrideHours) <= 4)
    }

    private func date(minutes: Int) -> Date {
        start.addingTimeInterval(Double(minutes) * 60)
    }

    private func drink(_ id: String, type: String, minute: Int, quantity: Int = 1) -> DrinkEntry {
        DrinkEntry(
            id: id, eventId: "night", drinkTypeId: type, timestamp: date(minutes: minute), quantity: quantity,
            comment: nil, volumeOverrideMl: nil, abvOverride: nil
        )
    }
}
