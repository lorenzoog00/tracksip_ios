import Charts
import SwiftUI
import UIKit

struct NightBACChartData {
    struct Hour: Identifiable {
        let start: Date
        let end: Date
        let firstDrinkTime: Date
        let drinks: [Drink]

        var id: Date { start }
        var summary: String { drinks.map { "\($0.name) ×\($0.quantity)" }.joined(separator: " · ") }
    }

    struct Drink {
        let name: String
        let quantity: Int
    }

    let start: Date
    let end: Date
    let current: BACDataPoint
    let history: [BACDataPoint]
    let projection: [BACDataPoint]
    let hours: [Hour]
    let isFinished: Bool

    init(
        eventStart: Date, now: Date, currentBAC: Double, samples: [BACDataPoint],
        entries: [DrinkEntry], drinkTypes: [DrinkType], calendar: Calendar = .current,
        isFinished: Bool = false
    ) {
        let logged = entries.filter { $0.timestamp <= now }
        let start = min(eventStart, now, logged.map(\.timestamp).min() ?? now, samples.first?.date ?? now)
        let current = BACDataPoint(date: now, bac: currentBAC)
        var history = samples.filter { $0.date < now }
        if start < (history.first?.date ?? now) {
            history.insert(BACDataPoint(date: start, bac: 0), at: 0)
        }
        history.append(current)

        var projection = [current] + samples.filter { $0.date > now }
        let last = projection.last ?? current
        let oneHourAhead = now.addingTimeInterval(3600)
        if !isFinished && last.bac == 0 && last.date < oneHourAhead {
            projection.append(BACDataPoint(date: oneHourAhead, bac: 0))
        }

        self.start = start
        self.end = max(projection.last?.date ?? now, start.addingTimeInterval(1))
        self.current = current
        self.history = history
        self.projection = projection
        self.hours = Self.groupByHour(entries: logged, drinkTypes: drinkTypes, calendar: calendar)
        self.isFinished = isFinished
    }

    var yMax: Double {
        let peak = max(history.map(\.bac).max() ?? 0, projection.map(\.bac).max() ?? 0)
        return max(peak * 1.18, 0.04)
    }

    func bac(at date: Date) -> Double {
        BACCalculator.interpolatedBAC(at: date, sorted: date <= current.date ? history : projection)
    }

    func hour(containing date: Date) -> Hour? {
        hours.first { date >= $0.start && date < $0.end }
    }

    private static func groupByHour(entries: [DrinkEntry], drinkTypes: [DrinkType], calendar: Calendar) -> [Hour] {
        let byHour = Dictionary(grouping: entries) { entry in
            calendar.dateInterval(of: .hour, for: entry.timestamp)?.start ?? entry.timestamp
        }
        return byHour.compactMap { start, entries -> Hour? in
            guard let firstDrinkTime = entries.map(\.timestamp).min() else { return nil }
            let drinks = Dictionary(grouping: entries, by: \.drinkTypeId).map { id, entries in
                Drink(
                    name: drinkTypes.first { $0.id == id }?.name ?? "Unknown drink",
                    quantity: entries.reduce(0) { $0 + $1.quantity }
                )
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return Hour(start: start, end: start.addingTimeInterval(3600), firstDrinkTime: firstDrinkTime, drinks: drinks)
        }.sorted { $0.start < $1.start }
    }
}

struct NightBACChartCard: View {
    let data: NightBACChartData
    var externalSelection: Binding<Date?>? = nil
    var relatedTime: Date? = nil
    @State private var localSelection: Date?
    @State private var isExpanded = false
    @State private var chartScene: UIWindowScene?
    @State private var returnOrientation: UIInterfaceOrientationMask?

    private var selection: Binding<Date?> { externalSelection ?? $localSelection }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("BAC Timeline", systemImage: "waveform.path.ecg")
                .font(.headline)
                .foregroundStyle(AppColors.text)
            NightBACPlot(data: data, selection: selection, tickCount: 4, relatedTime: relatedTime)
                .frame(height: 160)
            chartLegend
            NightBACSelection(data: data, selection: selection.wrappedValue)
            HStack {
                Text("Tap or drag to explore")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button(action: expand) {
                    Label("View Chart", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .tint(AppColors.accent)
            }
        }
        .padding(16)
        .premiumCard(radius: 14)
        .fullScreenCover(isPresented: $isExpanded, onDismiss: restoreOrientation) {
            expandedChart
                .statusBarHidden()
                .onAppear {
                    chartScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
                }
        }
    }

    private func expand() {
        chartScene = PresentationAnchor.root()?.view.window?.windowScene
        let orientation: UIInterfaceOrientation?
        if #available(iOS 26.0, *) {
            orientation = chartScene?.effectiveGeometry.interfaceOrientation
        } else {
            orientation = chartScene?.interfaceOrientation
        }
        switch orientation {
        case .portrait: returnOrientation = .portrait
        case .portraitUpsideDown: returnOrientation = .portraitUpsideDown
        case .landscapeLeft: returnOrientation = .landscapeLeft
        case .landscapeRight: returnOrientation = .landscapeRight
        default: returnOrientation = nil
        }
        isExpanded = true
    }

    private func restoreOrientation() {
        if let returnOrientation {
            chartScene?.requestGeometryUpdate(.iOS(interfaceOrientations: returnOrientation))
        }
        chartScene = nil
        returnOrientation = nil
    }

    private var expandedChart: some View {
        GeometryReader { geometry in
            let size = geometry.size
            if size.height > size.width {
                // The scene can refuse landscape in a constrained window.
                wideChart(width: size.height)
                    .frame(width: size.height, height: size.width)
                    .rotationEffect(.degrees(90))
                    .frame(width: size.width, height: size.height)
            } else {
                wideChart(width: size.width)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
    }

    private func wideChart(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BAC Timeline").font(.headline)
                Spacer()
                Button("Done") { isExpanded = false }
                    .font(.headline)
                    .tint(AppColors.accent)
                    .frame(minHeight: 44)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    NightBACPlot(data: data, selection: selection, tickCount: 6, relatedTime: relatedTime)
                        .frame(minHeight: 110, maxHeight: .infinity)
                    chartLegend
                    NightBACSelection(data: data, selection: selection.wrappedValue)
                }
                .frame(maxWidth: .infinity)
                hourlyLog
                    .frame(width: min(width * 0.32, 280))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(AppColors.text)
    }

    private var chartLegend: some View {
        HStack(spacing: 14) {
            Label("Estimated BAC", systemImage: "line.diagonal")
                .foregroundStyle(AppColors.accentWarm)
            Label(data.isFinished ? "After close" : "Projection", systemImage: "ellipsis")
                .foregroundStyle(AppColors.water)
        }
        .font(.caption)
    }

    private var hourlyLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drinks by hour")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if data.hours.isEmpty {
                Text("No drinks logged yet.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(data.hours) { hour in
                            Button { selection.wrappedValue = hour.firstDrinkTime } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(hour.start, format: .dateTime.hour().minute())
                                        .font(.subheadline.weight(.semibold))
                                    Text(hour.summary)
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(
                                    data.hour(containing: selection.wrappedValue ?? data.current.date)?.id == hour.id
                                        ? AppColors.accentDim : AppColors.surface,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct NightBACPlot: View {
    let data: NightBACChartData
    @Binding var selection: Date?
    let tickCount: Int
    let relatedTime: Date?

    var body: some View {
        let time = selection.map { min(max($0, data.start), data.end) } ?? data.current.date
        Chart {
            if let relatedTime, (data.start...data.end).contains(relatedTime), relatedTime != time {
                RectangleMark(
                    xStart: .value("Range start", min(time, relatedTime)),
                    xEnd: .value("Range end", max(time, relatedTime)),
                    yStart: .value("Baseline", 0.0), yEnd: .value("Chart height", data.yMax)
                )
                .foregroundStyle(AppColors.accentWarm.opacity(0.09))
            }
            ForEach(data.history, id: \.date) { point in
                AreaMark(x: .value("Time", point.date), y: .value("BAC", point.bac))
                    .foregroundStyle(AppColors.accent.opacity(0.12))
                LineMark(
                    x: .value("Time", point.date), y: .value("BAC", point.bac),
                    series: .value("Series", "Estimated BAC")
                )
                .foregroundStyle(AppColors.accentWarm)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(data.projection, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date), y: .value("BAC", point.bac),
                    series: .value("Series", "Projection")
                )
                .foregroundStyle(AppColors.water)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            RuleMark(x: .value(data.isFinished ? "Night ended" : "Now", data.current.date))
                .foregroundStyle(AppColors.textSecondary.opacity(0.45))
            ForEach(data.hours) { hour in
                PointMark(x: .value("Drinks logged", hour.firstDrinkTime), y: .value("BAC", data.bac(at: hour.firstDrinkTime)))
                    .foregroundStyle(AppColors.accent)
                    .symbolSize(18)
            }
            if let relatedTime, (data.start...data.end).contains(relatedTime), relatedTime != time {
                RuleMark(x: .value("Related time", relatedTime))
                    .foregroundStyle(AppColors.accent.opacity(0.55))
                    .lineStyle(StrokeStyle(dash: [3, 3]))
                PointMark(x: .value("Related time", relatedTime), y: .value("Estimated BAC", data.bac(at: relatedTime)))
                    .foregroundStyle(AppColors.accent)
                    .symbolSize(32)
            }
            if time != data.current.date {
                RuleMark(x: .value("Selected time", time))
                    .foregroundStyle(AppColors.text.opacity(0.35))
            }
            PointMark(x: .value("Selected time", time), y: .value("Estimated BAC", data.bac(at: time)))
                .foregroundStyle(AppColors.text)
                .symbolSize(40)
        }
        .chartXScale(domain: data.start...data.end)
        .chartYScale(domain: 0...data.yMax)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: tickCount)) { value in
                AxisGridLine().foregroundStyle(AppColors.border)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(AppColors.border)
                AxisValueLabel {
                    if let bac = value.as(Double.self) {
                        Text(String(format: "%.2f", bac))
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .accessibilityLabel("Estimated BAC over time")
        .accessibilityHint("Select a time to see the estimate and the drinks logged that hour")
    }
}

private struct NightBACSelection: View {
    let data: NightBACChartData
    let selection: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let time = selection.map { min(max($0, data.start), data.end) } ?? data.current.date
        let isFuture = time > data.current.date
        let bac = data.bac(at: time)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(time, format: .dateTime.hour().minute())
                if time == data.current.date {
                    Text(data.isFinished ? "Night ended" : "Now").foregroundStyle(AppColors.textSecondary)
                } else if isFuture {
                    Text("Projected").foregroundStyle(AppColors.water)
                }
                Spacer(minLength: 4)
                Text(String(format: "%.3f%% BAC", bac))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: bac * 1000))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.text)
            if isFuture {
                Text("Assumes no more drinks.")
            } else if let hour = data.hour(containing: time) {
                Text("This hour · \(hour.summary)")
            } else {
                Text("No drinks logged this hour.")
            }
        }
        .font(.caption)
        .foregroundStyle(AppColors.textSecondary)
    }
}
