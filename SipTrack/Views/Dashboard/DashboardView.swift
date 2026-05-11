import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var tab = 0
    @State private var monthOffset = 0

    private var allTime: AllTimeStats {
        AnalyticsEngine.allTime(
            events: appState.events,
            entries: appState.entries,
            drinkTypes: appState.allDrinkTypes,
            profile: appState.userProfile
        )
    }

    private var monthly: MonthlyStats {
        let comps = Calendar.current.dateComponents(
            [.year, .month],
            from: Calendar.current.date(byAdding: .month, value: monthOffset, to: Date())!
        )
        return AnalyticsEngine.monthly(
            year: comps.year!,
            month: comps.month!,
            events: appState.events,
            entries: appState.entries,
            drinkTypes: appState.allDrinkTypes,
            profile: appState.userProfile
        )
    }

    private var weeklyTrend: [WeeklyBucket] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "M/d"
        return (0..<8).map { offset in
            let ref = cal.date(byAdding: .weekOfYear, value: offset - 7, to: Date())!
            guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref)),
                  let weekEnd   = cal.date(byAdding: .day, value: 6, to: weekStart) else {
                return WeeklyBucket(label: "", drinks: 0, nights: 0)
            }
            let events = appState.events.filter {
                $0.endTime != nil && $0.startTime >= weekStart && $0.startTime <= weekEnd
            }
            let drinks = events.reduce(0) { $0 + appState.totalDrinks(for: $1.id) }
            return WeeklyBucket(label: fmt.string(from: weekStart), drinks: drinks, nights: events.count)
        }
    }

    private var dayOfWeekData: [DayBucket] {
        let dayMap: [(String, Int)] = [
            ("Mon", 2), ("Tue", 3), ("Wed", 4), ("Thu", 5),
            ("Fri", 6), ("Sat", 7), ("Sun", 1)
        ]
        return dayMap.map { (label, weekday) in
            let dayEvents = appState.events.filter {
                $0.endTime != nil &&
                Calendar.current.component(.weekday, from: $0.startTime) == weekday
            }
            let total = dayEvents.reduce(0) { $0 + appState.totalDrinks(for: $1.id) }
            let avg   = dayEvents.isEmpty ? 0.0 : Double(total) / Double(dayEvents.count)
            return DayBucket(day: label, avgDrinks: avg, nights: dayEvents.count)
        }
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: Custom Tab Selector
                StatsTabBar(selected: $tab)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if tab == 2 {
                    CompareView()
                } else {
                    ScrollView {
                        if tab == 0 {
                            AllTimeView(
                                stats: allTime,
                                weeklyTrend: weeklyTrend,
                                dayOfWeekData: dayOfWeekData
                            )
                        } else {
                            MonthlyView(stats: monthly, offset: $monthOffset)
                        }
                    }
                }
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tab Bar

private struct StatsTabBar: View {
    @Binding var selected: Int
    private let tabs = ["All Time", "Monthly", "Compare"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { idx, title in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = idx }
                } label: {
                    VStack(spacing: 9) {
                        Text(title)
                            .font(.system(size: 13, weight: selected == idx ? .bold : .regular))
                            .foregroundStyle(selected == idx ? AppColors.text : AppColors.textTertiary)
                            .animation(.easeInOut(duration: 0.18), value: selected)

                        ZStack {
                            Rectangle()
                                .fill(AppColors.border.opacity(0.35))
                                .frame(height: 1.5)
                            if selected == idx {
                                Rectangle()
                                    .fill(AppColors.accent)
                                    .frame(height: 2)
                                    .shadow(color: AppColors.accent.opacity(0.6), radius: 4, x: 0, y: 0)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Data Types

private struct WeeklyBucket: Identifiable {
    let id = UUID()
    let label: String
    let drinks: Int
    let nights: Int
}

private struct DayBucket: Identifiable {
    let id = UUID()
    let day: String
    let avgDrinks: Double
    let nights: Int
}

// MARK: - All Time View

private struct AllTimeView: View {
    let stats: AllTimeStats
    let weeklyTrend: [WeeklyBucket]
    let dayOfWeekData: [DayBucket]

    var body: some View {
        VStack(spacing: 14) {
            // Primary stat grid — 3 column compact
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCard(value: "\(stats.totalEvents)",                                    label: "Total Nights",   icon: "moon.fill")
                StatCard(value: "\(stats.totalDrinks)",                                    label: "Total Drinks",   icon: "wineglass.fill")
                StatCard(value: String(format: "%.1f", stats.avgDrinksPerNight),           label: "Avg / Night",    icon: "chart.bar.fill")
                StatCard(value: "\(Int(stats.avgMinutesPerDrink))m",                       label: "Avg / Drink",    icon: "clock.fill")
                StatCard(value: "\(Int(stats.totalAlcoholG))g",                            label: "Total Alcohol",  icon: "flask.fill")
                StatCard(value: "\(Int(stats.totalCalories))",                             label: "Total Calories", icon: "flame.fill")
            }
            .padding(.horizontal)

            if stats.avgMeanBAC > 0 {
                MeanBACCard(avgMeanBAC: stats.avgMeanBAC, totalEvents: stats.totalEvents)
            }

            if let record = stats.recordNight {
                RecordCard(title: "Record Night", name: record.name, date: record.date, count: record.total)
            }

            // Streak row
            HStack(spacing: 10) {
                StreakCard(value: stats.weeklyStreak,  label: "Week Streak",    icon: "calendar.badge.clock")
                StreakCard(value: stats.weekendStreak, label: "Weekend Streak", icon: "party.popper.fill")
            }
            .padding(.horizontal)

            if weeklyTrend.contains(where: { $0.drinks > 0 }) {
                WeeklyTrendCard(data: weeklyTrend)
            }

            if dayOfWeekData.contains(where: { $0.nights > 0 }) {
                DayOfWeekCard(data: dayOfWeekData)
            }

            if !stats.insights.isEmpty {
                InsightsCard(insights: stats.insights)
            }

            Color.clear.frame(height: 32)
        }
        .padding(.top, 16)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.accent.opacity(0.4))
                    .padding(.top, 2)
            }

            Spacer()

            Text(value)
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(label.uppercased())
                .font(.system(size: 7, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .premiumCard(radius: 14)
    }
}

// MARK: - Streak Card

private struct StreakCard: View {
    let value: Int
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(value > 0 ? AppColors.accent.opacity(0.65) : AppColors.textTertiary)

            Spacer()

            Text("\(value)")
                .font(.system(size: 38, weight: .black, design: .monospaced))
                .foregroundStyle(value > 0 ? AppColors.accent : AppColors.textTertiary)

            Text(label.uppercased())
                .font(.system(size: 7, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .premiumCard(
            radius: 16,
            tint: AppColors.accent,
            tintOpacity: value > 0 ? 0.04 : 0
        )
    }
}

// MARK: - Mean BAC Card

private struct MeanBACCard: View {
    let avgMeanBAC: Double
    let totalEvents: Int

    private var stage: IntoxicationStage { IntoxicationStage.stage(for: avgMeanBAC) }
    private var gaugePosition: Double { min(avgMeanBAC / 0.28, 1.0) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AVG MEAN BAC")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(2.5)
                        .foregroundStyle(AppColors.textTertiary)

                    Text(String(format: "%.3f%%", avgMeanBAC))
                        .font(.system(size: 36, weight: .black, design: .monospaced))
                        .foregroundStyle(stage.color)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(stage.color)
                            .frame(width: 5, height: 5)
                        Text(stage.name.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(stage.color.opacity(0.75))
                    }
                }

                Spacer()

                VStack(spacing: 6) {
                    BACGauge(position: gaugePosition, color: stage.color)
                        .frame(width: 88, height: 52)

                    Text("RANGE")
                        .font(.system(size: 7, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            Rectangle()
                .fill(AppColors.border.opacity(0.4))
                .frame(height: 1)
                .padding(.top, 14)
                .padding(.bottom, 10)

            HStack {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
                Text("across \(totalEvents) night\(totalEvents == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
            }
        }
        .padding(18)
        .premiumCard(radius: 18, tint: stage.color, tintOpacity: 0.05)
        .padding(.horizontal)
    }
}

// MARK: - BAC Arc Gauge

private struct BACGauge: View {
    let position: Double  // 0.0–1.0
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let cx  = size.width / 2
            let cy  = size.height
            let r   = min(size.width, size.height * 2) / 2 - 5
            let lw: CGFloat = 6

            // Track arc (180° → 360°, semicircle opens upward)
            var track = Path()
            track.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                         startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            ctx.stroke(track, with: .color(Color.white.opacity(0.07)),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round))

            // Colored fill arc
            let endDeg = 180.0 + position * 180.0
            var fill = Path()
            fill.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                        startAngle: .degrees(180), endAngle: .degrees(endDeg), clockwise: false)
            ctx.stroke(fill, with: .color(color.opacity(0.35)),
                       style: StrokeStyle(lineWidth: lw + 6, lineCap: .round))
            ctx.stroke(fill, with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round))

            // Needle dot at arc tip
            let endRad = endDeg * Double.pi / 180.0
            let nx = cx + CGFloat(cos(endRad)) * r
            let ny = cy + CGFloat(sin(endRad)) * r
            var dot = Path()
            dot.addEllipse(in: CGRect(x: nx - 4, y: ny - 4, width: 8, height: 8))
            ctx.fill(dot, with: .color(color))
            var innerDot = Path()
            innerDot.addEllipse(in: CGRect(x: nx - 2, y: ny - 2, width: 4, height: 4))
            ctx.fill(innerDot, with: .color(Color.white.opacity(0.5)))
        }
    }
}

// MARK: - Record Card

private struct RecordCard: View {
    let title: String
    let name: String
    let date: Date
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(AppColors.textTertiary)
                Text(name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.text)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                    .foregroundStyle(AppColors.accent)
                Text("DRINKS")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .premiumCard(radius: 16, tint: AppColors.accent, tintOpacity: 0.03)
        .padding(.horizontal)
    }
}

// MARK: - Insights Card

private struct InsightsCard: View {
    let insights: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.accent.opacity(0.7))
                Text("INSIGHTS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(insights, id: \.self) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(AppColors.accent.opacity(0.5))
                            .frame(width: 2, height: 2)
                            .padding(.top, 6)
                        Text(insight)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.text)
                            .lineSpacing(3)
                    }
                }
            }
        }
        .padding(18)
        .premiumCard(radius: 16)
        .padding(.horizontal)
    }
}

// MARK: - Weekly Trend Chart

private struct WeeklyTrendCard: View {
    let data: [WeeklyBucket]

    private var avgDrinks: Double {
        let active = data.filter { $0.drinks > 0 }
        guard !active.isEmpty else { return 0 }
        return Double(active.reduce(0) { $0 + $1.drinks }) / Double(active.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEKLY ACTIVITY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2.5)
                        .foregroundStyle(AppColors.textSecondary)
                    Text("Last 8 weeks")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                }
                Spacer()
            }

            Chart {
                if avgDrinks > 0 {
                    RuleMark(y: .value("Avg", avgDrinks))
                        .foregroundStyle(AppColors.textTertiary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .trailing, alignment: .center) {
                            Text("avg")
                                .font(.system(size: 8))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                }
                ForEach(data) { item in
                    BarMark(
                        x: .value("Week", item.label),
                        y: .value("Drinks", item.drinks)
                    )
                    .foregroundStyle(
                        item.drinks == 0 ? AppColors.border.opacity(0.3) :
                        Double(item.drinks) > avgDrinks ? AppColors.accent : AppColors.accentDim.opacity(0.6)
                    )
                    .cornerRadius(5)
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel {
                        if let s = val.as(String.self) {
                            Text(s).font(.system(size: 8)).foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { val in
                    AxisGridLine().foregroundStyle(AppColors.border.opacity(0.3))
                    AxisValueLabel {
                        if let i = val.as(Int.self) {
                            Text("\(i)").font(.system(size: 9)).foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(18)
        .premiumCard(radius: 16)
        .padding(.horizontal)
    }
}

// MARK: - Day of Week Card

private struct DayOfWeekCard: View {
    let data: [DayBucket]

    private var maxAvg: Double { data.map(\.avgDrinks).max() ?? 1 }
    private var topDay: String? { data.max(by: { $0.avgDrinks < $1.avgDrinks })?.day }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR TYPICAL WEEK")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2.5)
                        .foregroundStyle(AppColors.textSecondary)
                    if let top = topDay {
                        Text("\(top)s are your biggest night")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data) { item in
                    let fraction = maxAvg > 0 ? item.avgDrinks / maxAvg : 0
                    let isTop    = item.day == topDay && item.nights > 0
                    VStack(spacing: 5) {
                        if item.nights > 0 {
                            Text(String(format: "%.1f", item.avgDrinks))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(isTop ? AppColors.accent : AppColors.textSecondary)
                        }
                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                isTop      ? AppColors.accent :
                                item.nights > 0 ? AppColors.accentDim :
                                AppColors.border.opacity(0.2)
                            )
                            .frame(height: max(CGFloat(fraction) * 88, item.nights > 0 ? 4 : 2))
                            .frame(maxWidth: .infinity)
                            .shadow(
                                color: isTop ? AppColors.accent.opacity(0.4) : .clear,
                                radius: 6, x: 0, y: 3
                            )
                        Text(item.day)
                            .font(.system(size: 9, weight: isTop ? .bold : .regular))
                            .foregroundStyle(isTop ? AppColors.accent : AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)

            Text("Avg drinks per night, by day of week")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(18)
        .premiumCard(radius: 16)
        .padding(.horizontal)
    }
}

// MARK: - Monthly View

private struct MonthlyView: View {
    let stats: MonthlyStats
    @Binding var offset: Int

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        let date = Calendar.current.date(byAdding: .month, value: offset, to: Date())!
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 14) {
            // Month navigator
            HStack {
                Button { offset -= 1 } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 44, height: 40)
                }
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.text)
                Spacer()
                Button { if offset < 0 { offset += 1 } } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(offset < 0 ? AppColors.textSecondary : AppColors.textTertiary)
                        .frame(width: 44, height: 40)
                }
                .disabled(offset >= 0)
            }
            .padding(.horizontal)

            if stats.totalEvents == 0 {
                VStack(spacing: 14) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColors.textTertiary.opacity(0.4))
                    Text("No nights this month")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.top, 56)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatCard(value: "\(stats.totalEvents)",                                  label: "Nights",    icon: "moon.fill")
                    StatCard(value: "\(stats.totalDrinks)",                                  label: "Drinks",    icon: "wineglass.fill")
                    StatCard(value: String(format: "%.1f", stats.avgDrinksPerNight),         label: "Avg / Night", icon: "chart.bar.fill")
                    StatCard(value: "\(Int(stats.totalCalories))",                           label: "Calories",  icon: "flame.fill")
                }
                .padding(.horizontal)

                if stats.avgMeanBAC > 0 {
                    MeanBACCard(avgMeanBAC: stats.avgMeanBAC, totalEvents: stats.totalEvents)
                }

                if let record = stats.recordNight {
                    RecordCard(title: "Best Night", name: record.name, date: record.date, count: record.total)
                }

                if !stats.drinksByType.isEmpty {
                    DrinksByTypeCard(items: stats.drinksByType)
                }
            }

            Color.clear.frame(height: 32)
        }
        .padding(.top, 12)
    }
}

// MARK: - Drinks By Type Card

private struct DrinksByTypeCard: View {
    let items: [(name: String, count: Int)]

    private var maxCount: Int { items.map(\.count).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BY TYPE")
                .font(.system(size: 9, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: 12) {
                ForEach(items.prefix(6), id: \.name) { item in
                    HStack(spacing: 10) {
                        Text(item.name)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.text)
                            .frame(width: 88, alignment: .leading)

                        GeometryReader { geo in
                            let fraction = CGFloat(item.count) / CGFloat(maxCount)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppColors.border.opacity(0.25))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [AppColors.accentWarm, AppColors.accent],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * fraction)
                            }
                        }
                        .frame(height: 7)

                        Text("×\(item.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .padding(18)
        .premiumCard(radius: 16)
        .padding(.horizontal)
    }
}
