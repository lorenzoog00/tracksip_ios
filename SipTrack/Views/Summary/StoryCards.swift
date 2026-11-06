import SwiftUI
import UIKit

struct StoryCardView: View {
    let story: NightStory
    let moment: StoryMoment
    let image: UIImage?
    let caption: String?
    var showsSpine = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if moment.id == "end" {
                    StoryEndCardView(story: story, caption: caption, reservesControls: showsSpine)
                        .transition(reduceMotion ? .identity : .opacity)
                } else {
                    photoCard(size: geometry.size)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
        }
        .background(AppColors.background)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func photoCard(size: CGSize) -> some View {
        let stage = IntoxicationStage.stage(for: moment.bac)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(moment.timestamp, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .contentTransition(reduceMotion ? .identity : .opacity)
                Spacer()
                Image(systemName: "drop.fill").foregroundStyle(AppColors.accentWarm)
                    .accessibilityLabel("Tracksip")
            }
            Spacer(minLength: 12)
            if !story.review.timeline.isEmpty {
                Text(String(format: "%.3f%%", moment.bac))
                    .font(.system(size: min(size.width * 0.18, 72), weight: .bold, design: .serif))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: moment.bac * 1000))
                    .accessibilityLabel(String(format: "Estimated BAC %.3f percent", moment.bac))
            }
            Text(description(stage: stage))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                .contentTransition(reduceMotion ? .identity : .opacity)
            if let caption, !caption.isEmpty {
                Text(caption).font(.body).lineLimit(2)
                    .contentTransition(reduceMotion ? .identity : .opacity)
            }
            if showsSpine, !story.review.timeline.isEmpty {
                StorySpineView(path: story.review.path, ceiling: story.review.ceiling, time: moment.timestamp)
                    .frame(height: 36)
                    .padding(.top, 10)
            } else {
                Color.clear.frame(height: 46)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, showsSpine ? 92 : 70)
        .padding(.bottom, showsSpine ? 60 : 42)
        .frame(width: size.width, height: size.height)
        .background {
            photoBackdrop(color: stage.color)
                .ignoresSafeArea()
        }
    }

    private func photoBackdrop(color: Color) -> some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [color.opacity(0.28), AppColors.background], startPoint: .topTrailing, endPoint: .bottomLeading)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .id(moment.id)
                        .transition(reduceMotion ? .identity : .opacity)
                        .zIndex(1)
                }
                LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.25),
                                       .init(color: .clear, location: 0.43), .init(color: .black.opacity(0.91), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .zIndex(2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func description(stage: IntoxicationStage) -> String {
        if story.review.timeline.isEmpty {
            return moment.id == "start" ? "Night start" : "No alcohol logged"
        }
        if moment.id == "start", let limit = story.review.ceiling.line {
            return String(format: "%@ %.3f%% · Estimated BAC", story.review.ceiling.name, limit)
        }
        if moment.id == "peak" { return "Estimated peak during the night" }
        if let limit = story.review.ceiling.line, moment.bac > limit {
            return "Estimated BAC above \(story.review.ceiling.name.lowercased())"
        }
        return "Estimated BAC · \(stage.name)"
    }
}

struct StorySpineView: View {
    let path: BACPath
    let ceiling: StoryCeiling
    let time: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: SpineSweep?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: sweep == nil || reduceMotion)) { timeline in
            spine(at: reduceMotion ? time : (sweep?.date(at: timeline.date) ?? time))
        }
        .onChange(of: time) { old, new in
            guard !reduceMotion else { return }
            let now = Date.now
            sweep = SpineSweep(from: sweep?.date(at: now) ?? old, to: new, started: now)
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { sweep = nil }
        }
        .task(id: sweep?.started) {
            guard let sweep else { return }
            do { try await Task.sleep(for: .seconds(SpineSweep.duration)) } catch { return }
            if self.sweep?.started == sweep.started { self.sweep = nil }
        }
        .accessibilityHidden(true)
    }

    private func spine(at time: Date) -> some View {
        Canvas { context, size in
            var context = context
            let bounds = CGSize(width: max(1, size.width - 8), height: max(1, size.height - 8))
            context.translateBy(x: 4, y: 4)
            let yMax = path.yMax(ceiling: ceiling.line)
            if let limit = ceiling.line {
                let y = path.point(at: path.start, bac: limit, in: bounds, yMax: yMax).y
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: bounds.width, y: y))
                context.stroke(line, with: .color(.white.opacity(ceiling.isPersonal ? 0.55 : 0.27)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            let curve = Path(path.cgPath(in: bounds, yMax: yMax))
            let bac = BACCalculator.interpolatedBAC(at: time, sorted: path.samples)
            let dot = path.point(at: time, bac: bac, in: bounds, yMax: yMax)
            context.stroke(curve, with: .color(AppColors.accentWarm.opacity(0.27)), lineWidth: 1)
            var revealed = context
            revealed.clip(to: Path(CGRect(x: -1, y: -2, width: dot.x + 2, height: bounds.height + 4)))
            revealed.stroke(curve, with: .color(AppColors.accentWarm), lineWidth: 1.5)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)),
                         with: .color(AppColors.accentWarm.opacity(0.18)))
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .color(.white))
        }
    }
}

private struct SpineSweep {
    static let duration = 0.30
    let from: Date
    let to: Date
    let started: Date

    func date(at frame: Date) -> Date {
        let progress = min(1, max(0, frame.timeIntervalSince(started) / Self.duration))
        let eased = progress * progress * (3 - 2 * progress)
        return from.addingTimeInterval(to.timeIntervalSince(from) * eased)
    }
}

private struct StoryEndCardView: View {
    let story: NightStory
    let caption: String?
    let reservesControls: Bool

    private var review: NightReview { story.review }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Spacer(minLength: reservesControls ? 84 : 54)
            Text(review.event.displayName)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(review.event.startTime, format: .dateTime.month(.wide).day().year())
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
            Text(NightReview.duration(Int(review.end.timeIntervalSince(review.event.startTime) / 60)))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)

            HStack(alignment: .top, spacing: 10) {
                stat("Drinks", value: "\(review.drinkCount)")
                stat(peakLabel, value: review.peak.map { String(format: "%.3f%%", $0.bac) } ?? "—")
                stat("Waters logged", value: "\(review.waters.count)")
            }

            recapBlock(icon: "figure.run", title: "Estimated exercise equivalents", text: energyText)
            recapBlock(icon: "waveform.path.ecg", title: "BAC context", text: limitText)
            if let note = caption ?? reportLine ?? story.suggestions["end"] ?? review.highlights.first?.detail, !note.isEmpty {
                Text(note).font(.caption).lineLimit(3).foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 12)
            Label("Tracksip", systemImage: "drop.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.accentWarm)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, reservesControls ? 60 : 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [AppColors.surfaceTop, AppColors.background], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var energyText: String {
        guard review.calories > 0 else { return "No drink calories logged." }
        let activities = ActivityEquivalence.allCases.map { activity in
            "\(activity.name) \(activity.duration(calories: review.calories))"
        }
        return "\(Int(review.calories)) drink calories\n" + activities.joined(separator: " · ")
    }

    private var peakLabel: String {
        guard let peak = review.peak, peak.date > review.end else { return "Estimated peak" }
        return "Projected peak"
    }

    private var limitText: String {
        guard review.drinkCount > 0 else { return "No alcoholic drinks logged during this night." }
        guard !review.timeline.isEmpty else { return "No BAC estimate available for this log." }
        guard let limit = review.ceiling.line else {
            return String(format: "%@ %.3f%%. See the chart for the projected decline.", review.ceiling.name, review.ceiling.value)
        }
        let context = review.path.above(limit)
        let line = String(format: "%.3f%%", limit)
        guard context.seconds > 0 else {
            return "During the logged night, the estimate stayed at or below the \(review.ceiling.name.lowercased()) of \(line)."
        }
        let minutes = max(1, Int((context.seconds / 60).rounded()))
        let detail = context.lastReturn.map { " Estimated below at \(NightReview.time($0))." } ?? " Above the line at close."
        return "About \(NightReview.duration(minutes)) above the \(line) line during the night." + detail
    }

    private var reportLine: String? {
        guard let report = review.event.aiReport, let body = NightReportParser.parse(report).first?.body else { return nil }
        var first: String?
        body.enumerateSubstrings(in: body.startIndex..<body.endIndex, options: .bySentences) { sentence, _, _, stop in
            first = sentence
            stop = true
        }
        return first
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recapBlock(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.accentWarm)
            Text(text).font(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(12)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
