import Foundation
import Testing
@testable import siptrack

@MainActor
struct MorningPlanTests {
    /// The doc as `generateReport` stores and returns it: photos not ready yet,
    /// and no fallback or skip.
    private let pendingPhotosDoc = """
    {
      "type": "morning",
      "version": 2,
      "created_at": 1795161600000,
      "symptoms": ["headache", "wrecked"],
      "severity": "heavy",
      "safety": {"dontDrive": true, "medicalHelp": false},
      "plan": {
        "headline": "Tequila and a 3 AM finish. Water and salt first, food in an hour.",
        "rightNow": [
          {"icon": "drop.fill", "title": "Water + electrolytes", "why": "Six tequilas and one water left you dry."}
        ],
        "breakfast": {
          "itemId": "lib_123", "name": "Chilaquiles verdes", "why": "Salt and carbs after a late night.",
          "when": "around 10:30", "photoUrl": null
        },
        "fallback": null,
        "activities": [
          {"itemId": "lib_456", "name": "20-min walk", "why": "Daylight after a 3 AM finish.", "photoUrl": null}
        ],
        "skip": null
      }
    }
    """

    private let photoLink = "https://firebasestorage.googleapis.com/v0/b/demo/o/recovery-library%2Flib_123.jpg?alt=media&token=abc"

    /// The same doc as a callable result dictionary, with every photo ready
    /// and the optional sections filled.
    private var readyDoc: [String: Any] {
        let rightNow: [[String: String]] = [
            ["icon": "cup.and.saucer.fill", "title": "Ginger tea, small sips", "why": "Settles the nausea from last night's shots."],
            ["icon": "bed.double.fill", "title": "Back to bed for an hour", "why": "You got in at 4."],
        ]
        let breakfast: [String: String] = [
            "itemId": "lib_123", "name": "Plain toast", "why": "Easy on a stomach that's still turning.",
            "when": "when it stays down", "photoUrl": photoLink,
        ]
        let activities: [[String: String]] = [
            ["itemId": "lib_789", "name": "Couch and a movie", "why": "Rest beats a walk today.", "photoUrl": photoLink],
        ]
        var plan: [String: Any] = [:]
        plan["headline"] = "Nine drinks and nausea. Small sips first, food once it settles."
        plan["rightNow"] = rightNow
        plan["breakfast"] = breakfast
        plan["fallback"] = ["title": "Broth instead."] as [String: String]
        plan["activities"] = activities
        plan["skip"] = ["title": "Greasy fry-up", "why": "Grease hits a nauseous stomach hard."] as [String: String]
        var doc: [String: Any] = [:]
        doc["type"] = "morning"
        doc["version"] = 2
        doc["created_at"] = 1_795_161_600_000 as Int64
        doc["symptoms"] = ["nausea"] as [String]
        doc["severity"] = "very_heavy"
        doc["safety"] = ["dontDrive": false, "medicalHelp": true] as [String: Bool]
        doc["plan"] = plan
        return doc
    }

    @Test func serverDocWithNullPhotoAndFallbackDecodes() throws {
        let record = try MorningRecord(eventId: "night-1", serverData: Data(pendingPhotosDoc.utf8))
        #expect(record.id == "night-1")
        #expect(record.symptoms == [.headache, .wrecked])
        #expect(record.severity == "heavy")
        #expect(record.safety == PlanSafety(dontDrive: true, medicalHelp: false))
        #expect(record.createdAt == Date(timeIntervalSince1970: 1_795_161_600))
        #expect(record.plan.rightNow == [
            PlanRemedy(icon: "drop.fill", title: "Water + electrolytes", why: "Six tequilas and one water left you dry."),
        ])
        #expect(record.plan.breakfast.itemId == "lib_123")
        #expect(record.plan.breakfast.when == "around 10:30")
        #expect(record.plan.breakfast.photoUrl == nil)
        #expect(record.plan.fallback == nil)
        #expect(record.plan.skip == nil)
        #expect(record.plan.activities.count == 1)
        #expect(record.plan.activities.first?.when == nil)
        #expect(record.plan.activities.first?.photoUrl == nil)
    }

    @Test func serverDocWithAPhotoDecodesItToAURL() throws {
        let record = try MorningRecord(eventId: "night-2", serverJSON: readyDoc)
        let link = try #require(URL(string: photoLink))
        #expect(record.id == "night-2")
        #expect(record.symptoms == [.nausea])
        #expect(record.safety.medicalHelp)
        #expect(record.plan.breakfast.photoUrl == link)
        #expect(record.plan.activities.first?.photoUrl == link)
        #expect(record.plan.fallback == PlanFallback(title: "Broth instead."))
        #expect(record.plan.skip == PlanSkip(title: "Greasy fry-up", why: "Grease hits a nauseous stomach hard."))
        #expect(record.plan.rightNow.map(\.icon) == ["cup.and.saucer.fill", "bed.double.fill"])
    }

    @Test func recordRoundTripsThroughLocalPersistence() throws {
        let records = [
            try MorningRecord(eventId: "night-1", serverData: Data(pendingPhotosDoc.utf8)),
            try MorningRecord(eventId: "night-2", serverJSON: readyDoc),
        ]
        // DataStore's coders use ISO 8601 dates; check the default coders too.
        let iso = JSONEncoder()
        iso.dateEncodingStrategy = .iso8601
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        for record in records {
            let stored = try isoDecoder.decode(MorningRecord.self, from: iso.encode(record))
            #expect(stored == record)
            let plain = try JSONDecoder().decode(MorningRecord.self, from: JSONEncoder().encode(record))
            #expect(plain == record)
        }
        let byEvent = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let restored = try isoDecoder.decode([String: MorningRecord].self, from: iso.encode(byEvent))
        #expect(restored == byEvent)
    }

    @Test func docEncodesBackToTheServerShape() throws {
        let record = try MorningRecord(eventId: "night-2", serverJSON: readyDoc)
        let data = try JSONEncoder().encode(record.doc)
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [String: Any])
        #expect((json["created_at"] as? NSNumber)?.int64Value == 1_795_161_600_000)
        #expect(!json.keys.contains("createdAt"))
        #expect(!json.keys.contains("id"))
        let again = try MorningRecord(eventId: "night-2", serverData: data)
        #expect(again == record)
    }

    @Test func unknownSymptomsAndBrokenPhotoLinksDoNotFailThePlan() throws {
        var doc = readyDoc
        doc["symptoms"] = ["headache", "hungover"] as [String]
        var plan = try #require(doc["plan"] as? [String: Any])
        var breakfast = try #require(plan["breakfast"] as? [String: Any])
        breakfast["photoUrl"] = ""
        plan["breakfast"] = breakfast
        doc["plan"] = plan
        let record = try MorningRecord(eventId: "night-3", serverJSON: doc)
        #expect(record.symptoms == [.headache])
        #expect(record.plan.breakfast.photoUrl == nil)
    }

    @Test func aValueThatIsNotJSONThrowsInsteadOfCrashing() {
        #expect(throws: (any Error).self) {
            try MorningRecord(eventId: "night-4", serverJSON: ["created_at": Date()])
        }
    }

    @Test func sampleIsAFullPlanWithAllowedIconsAndNoNetwork() {
        let sample = MorningPlan.sample
        #expect(!sample.headline.isEmpty)
        #expect((1...3).contains(sample.rightNow.count))
        #expect((1...2).contains(sample.activities.count))
        #expect(sample.rightNow.allSatisfy { PlanRemedy.icons.contains($0.icon) })
        #expect(sample.breakfast.when != nil)
        #expect(sample.fallback != nil)
        #expect(sample.skip != nil)
        #expect(sample.breakfast.photoUrl == nil)
        #expect(sample.activities.allSatisfy { $0.photoUrl == nil })
    }

    @Test func remedyIconsMatchTheServerListAndUnknownOnesFallBack() {
        #expect(PlanRemedy.icons == [
            "drop.fill", "pills.fill", "cup.and.saucer.fill", "leaf.fill", "bed.double.fill", "sun.max.fill",
            "wind", "fork.knife", "bolt.heart.fill", "snowflake", "figure.walk", "moon.zzz.fill",
        ])
        #expect(PlanRemedy(icon: "pills.fill", title: "", why: "").symbolName == "pills.fill")
        #expect(PlanRemedy(icon: "not.a.symbol", title: "", why: "").symbolName == "checkmark.circle")
    }

    @Test func symptomsMatchTheServerNamesAndTheNotificationCopy() {
        #expect(Symptom.allCases.map(\.rawValue) == ["headache", "nausea", "wrecked", "dizzy", "anxious", "fine"])
        let titles = [Symptom.headache, .nausea, .wrecked, .fine].map { "\($0.emoji) \($0.label)" }
        #expect(titles == ["🤕 Headache", "🤢 Nausea", "😴 Wrecked", "💪 I'm fine"])
        #expect(Symptom.dizzy.label == "Dizzy")
        #expect(Symptom.anxious.label == "Anxious")
    }
}
