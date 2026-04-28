import SwiftUI

struct IntoxicationStage {
    let name: String
    let minBAC: Double
    let maxBAC: Double
    let color: Color
    let colorHex: String
    let blurb: String

    var range: ClosedRange<Double> { minBAC...maxBAC }
}

extension IntoxicationStage {
    static let all: [IntoxicationStage] = [
        IntoxicationStage(name: "Sober",      minBAC: 0.00, maxBAC: 0.02, color: Color(hex: "#2ED573"), colorHex: "#2ED573", blurb: "No noticeable effects."),
        IntoxicationStage(name: "Buzzed",     minBAC: 0.02, maxBAC: 0.05, color: Color(hex: "#7BED9F"), colorHex: "#7BED9F", blurb: "Mild relaxation, slight mood lift."),
        IntoxicationStage(name: "Tipsy",      minBAC: 0.05, maxBAC: 0.08, color: Color(hex: "#ECCC68"), colorHex: "#ECCC68", blurb: "Lowered inhibitions, slowed reaction time."),
        IntoxicationStage(name: "Impaired",   minBAC: 0.08, maxBAC: 0.15, color: Color(hex: "#FFA502"), colorHex: "#FFA502", blurb: "Slurred speech, impaired coordination. Do not drive."),
        IntoxicationStage(name: "Drunk",      minBAC: 0.15, maxBAC: 0.25, color: Color(hex: "#FF6348"), colorHex: "#FF6348", blurb: "Balance issues, memory lapses."),
        IntoxicationStage(name: "Very Drunk", minBAC: 0.25, maxBAC: 0.35, color: Color(hex: "#FF4757"), colorHex: "#FF4757", blurb: "Confusion, blackout risk."),
        IntoxicationStage(name: "Danger",     minBAC: 0.35, maxBAC: 0.50, color: Color(hex: "#B71540"), colorHex: "#B71540", blurb: "Risk of alcohol poisoning. Seek help immediately."),
    ]

    static func stage(for bac: Double) -> IntoxicationStage {
        all.last(where: { bac >= $0.minBAC }) ?? all[0]
    }

    static func barPosition(for bac: Double) -> Double {
        guard bac.isFinite else { return 0 }
        let clipped = max(0, min(bac, 0.50))
        return clipped / 0.50
    }
}
