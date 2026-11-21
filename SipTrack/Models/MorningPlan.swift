import Foundation

// MARK: - Symptoms

/// What the user picks at the morning check-in. Raw values are the names the
/// server's `validateMorning` accepts; `fine` is only ever sent alone.
enum Symptom: String, Codable, CaseIterable, Hashable {
    case headache, nausea, wrecked, dizzy, anxious, fine

    var emoji: String {
        switch self {
        case .headache: return "🤕"
        case .nausea:   return "🤢"
        case .wrecked:  return "😴"
        case .dizzy:    return "🌀"
        case .anxious:  return "😰"
        case .fine:     return "💪"
        }
    }

    var label: String {
        switch self {
        case .headache: return "Headache"
        case .nausea:   return "Nausea"
        case .wrecked:  return "Wrecked"
        case .dizzy:    return "Dizzy"
        case .anxious:  return "Anxious"
        case .fine:     return "I'm fine"
        }
    }
}

// MARK: - Plan

/// A "Right now" line: an SF Symbol from a fixed list, a title and a reason.
struct PlanRemedy: Codable, Hashable {
    var icon: String
    var title: String
    var why: String

    /// The only icons the server lets through (functions/recovery/plan.js).
    static let icons: [String] = [
        "drop.fill", "pills.fill", "cup.and.saucer.fill", "leaf.fill", "bed.double.fill", "sun.max.fill",
        "wind", "fork.knife", "bolt.heart.fill", "snowflake", "figure.walk", "moon.zzz.fill",
    ]

    /// `icon` when it is on the list, otherwise a neutral symbol, so a stored
    /// plan can never render a missing image.
    var symbolName: String { Self.icons.contains(icon) ? icon : "checkmark.circle" }
}

/// A breakfast or an activity from the photo library. `when` is only set on
/// the breakfast. `photoUrl` is nil until the photo exists (or forever, when
/// generation failed or was capped), and the view shows an icon tile then.
struct PlanPhotoItem: Codable, Hashable {
    var itemId: String
    var name: String
    var why: String
    var when: String?
    var photoUrl: URL?

    enum CodingKeys: String, CodingKey {
        case itemId, name, why, when, photoUrl
    }
}

extension PlanPhotoItem {
    // By hand so a malformed or empty `photoUrl` string becomes "no photo yet"
    // instead of failing the whole plan, as the synthesized URL decoding would.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try c.decode(String.self, forKey: .itemId)
        name = try c.decode(String.self, forKey: .name)
        why = try c.decode(String.self, forKey: .why)
        when = try c.decodeIfPresent(String.self, forKey: .when)
        let link = (try? c.decodeIfPresent(String.self, forKey: .photoUrl)) ?? nil
        photoUrl = link.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(itemId, forKey: .itemId)
        try c.encode(name, forKey: .name)
        try c.encode(why, forKey: .why)
        try c.encodeIfPresent(when, forKey: .when)
        try c.encodeIfPresent(photoUrl?.absoluteString, forKey: .photoUrl)
    }
}

/// The text-only "Stomach off?" alternative to the breakfast.
struct PlanFallback: Codable, Hashable {
    var title: String
}

/// The one myth to avoid.
struct PlanSkip: Codable, Hashable {
    var title: String
    var why: String
}

/// Mirrors `plan` in the stored morning doc (functions/recovery/morning.js
/// `assemblePlan`). `fallback` and `skip` arrive as `null` when absent.
struct MorningPlan: Codable, Hashable {
    var headline: String
    var rightNow: [PlanRemedy]
    var breakfast: PlanPhotoItem
    var fallback: PlanFallback?
    var activities: [PlanPhotoItem]
    var skip: PlanSkip?

    /// A realistic plan shown blurred behind the upgrade button for a free user
    /// who is out of plans. Static, so the locked state never makes a request.
    static let sample = MorningPlan(
        headline: "Tequila and five hours of sleep. Water and salt first, food in an hour, then get outside.",
        rightNow: [
            PlanRemedy(icon: "drop.fill", title: "Big glass of water + electrolytes",
                       why: "Salt matters as much as water. Sip, don't chug."),
            PlanRemedy(icon: "pills.fill", title: "Ibuprofen, not Tylenol",
                       why: "Acetaminophen is hard on a liver still clearing alcohol."),
        ],
        breakfast: PlanPhotoItem(itemId: "sample-breakfast", name: "Eggs on toast + a banana",
                                 why: "Gets your blood sugar back up. The banana replaces potassium.",
                                 when: "around 10:30", photoUrl: nil),
        fallback: PlanFallback(title: "Plain toast and broth instead."),
        activities: [
            PlanPhotoItem(itemId: "sample-walk", name: "20-min walk",
                          why: "Daylight resets you after a late night.", when: nil, photoUrl: nil),
            PlanPhotoItem(itemId: "sample-nap", name: "Nap before 3",
                          why: "Max 90 minutes so tonight's sleep still works.", when: nil, photoUrl: nil),
        ],
        skip: PlanSkip(title: "Hair of the dog", why: "It just pushes the hangover to later.")
    )
}

/// Safety facts computed by the server. The app renders the fixed lines from
/// these; the model never writes them.
struct PlanSafety: Codable, Hashable {
    var dontDrive: Bool
    var medicalHelp: Bool
}

// MARK: - Stored doc and record

/// The morning doc exactly as the server stores and returns it
/// (`users/{uid}/night_recoveries/{eventId}`, and `morning` in the callable
/// result): `created_at` is milliseconds since 1970 and there is no id.
/// `type` and `version` are ignored.
struct MorningDoc: Codable, Hashable {
    var symptoms: [Symptom]
    var severity: String
    var safety: PlanSafety
    var plan: MorningPlan
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case symptoms, severity, safety, plan
        case createdAt = "created_at"
    }
}

extension MorningDoc {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A symptom name this build doesn't know is dropped, not fatal.
        symptoms = try c.decode([String].self, forKey: .symptoms).compactMap(Symptom.init(rawValue:))
        severity = try c.decode(String.self, forKey: .severity)
        safety = try c.decode(PlanSafety.self, forKey: .safety)
        plan = try c.decode(MorningPlan.self, forKey: .plan)
        let millis = try c.decode(Double.self, forKey: .createdAt)
        createdAt = Date(timeIntervalSince1970: millis / 1000)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(symptoms, forKey: .symptoms)
        try c.encode(severity, forKey: .severity)
        try c.encode(safety, forKey: .safety)
        try c.encode(plan, forKey: .plan)
        try c.encode((createdAt.timeIntervalSince1970 * 1000).rounded(), forKey: .createdAt)
    }
}

/// A night's morning plan as the app keeps it: the server doc plus the event
/// id it belongs to. Its own Codable form (synthesized) is what local
/// persistence writes and reads; server data goes through `MorningDoc`.
struct MorningRecord: Codable, Identifiable, Hashable {
    /// The night's event id.
    var id: String
    var symptoms: [Symptom]
    /// `light`, `moderate`, `heavy` or `very_heavy`.
    var severity: String
    var safety: PlanSafety
    var plan: MorningPlan
    var createdAt: Date
}

extension MorningRecord {
    enum ServerDataError: Error {
        case notJSON
    }

    init(eventId: String, doc: MorningDoc) {
        self.init(id: eventId, symptoms: doc.symptoms, severity: doc.severity,
                  safety: doc.safety, plan: doc.plan, createdAt: doc.createdAt)
    }

    /// Decodes the server doc's JSON bytes.
    init(eventId: String, serverData: Data) throws {
        self.init(eventId: eventId, doc: try JSONDecoder().decode(MorningDoc.self, from: serverData))
    }

    /// Decodes the server doc from a callable result or snapshot dictionary.
    /// Throws instead of crashing when the value isn't plain JSON.
    init(eventId: String, serverJSON: Any) throws {
        guard JSONSerialization.isValidJSONObject(serverJSON) else { throw ServerDataError.notJSON }
        try self.init(eventId: eventId, serverData: try JSONSerialization.data(withJSONObject: serverJSON))
    }

    var doc: MorningDoc {
        MorningDoc(symptoms: symptoms, severity: severity, safety: safety, plan: plan, createdAt: createdAt)
    }
}
