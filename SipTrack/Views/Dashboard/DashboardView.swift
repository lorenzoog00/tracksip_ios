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
            drinkTypes: appState.allDrinkTypes
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
            drinkTypes: appState.allDrinkTypes
        )
    }

    private var weeklyTrend: [WeeklyBucket] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
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
                Picker("Tab", selection: $tab) {
                    Text("All Time").tag(0)
                    Text("Monthly").tag(1)
                    Text("Compare").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

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

// MARK: - All Time

private struct AllTimeView: View {
    let stats: AllTimeStats
    let weeklyTrend: [WeeklyBucket]
    let dayOfWeekData: [DayBucket]

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(value: "\(stats.totalEvents)",              label: "Total Nights",   icon: "moon.fill")
                StatCard(value: "\(stats.totalDrinks)",             label: "Total Drinks",   icon: "wineglass.fill")
                StatCard(value: String(format: "%.1f", stats.avgDrinksPerNight), label: "Avg / Night", icon: "chart.bar.fill")
                StatCard(value: "\(Int(stats.avgMinutesPerDrink))m", label: "Avg / Drink",   icon: "clock.fill")
                StatCard(value: "\(Int(stats.totalAlcoholG))g",     label: "Total Alcohol",  icon: "flask.fill")
                StatCard(value: "\(Int(stats.totalCalories))",      label: "Total Calories", icon: "flame.fill")
            }
            .padding(.horizontal)

            if let record = stats.recordNight {
                RecordCard(title: "Record Night", name: record.name, date: record.date, count: record.total)
            }

            HStack(spacing: 12) {
                StreakCard(value: stats.weeklyStreak, label: "Week Streak")
                StreakCard(value: stats.weekendStreak, label: "Weekend Streak")
            }
            .padding(.horizontal)

            if weeklyTrend.contains(where: { $0.drinks > 0 }) {
                WeeklyTrendCard(data: weeklyTrend)
            }

            if dayOfWeekData.contains(where: { $0.nights > 0 }) {
                DayOfWeekCard(data: dayOfWeekData)
            }

            if !stats.insights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Insights", systemImage: "lightbulb.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                    ForEach(stats.insights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundStyle(AppColors.accent)
                            Text(insight)
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.text)
                        }
                    }
                }
                .padding()
                .background(AppColors.surface)
                .cornerRadius(14)
                .padding(.horizontal)
            }

            Color.clear.frame(height: 32)
        }
        .padding(.top)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WEEKLY ACTIVITY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text("Last 8 weeks")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }

            Chart {
                if avgDrinks > 0 {
                    RuleMark(y: .value("Avg", avgDrinks))
                        .foregroundStyle(AppColors.textTertiary.opacity(0.4))
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
                        item.drinks == 0 ? AppColors.border.opacity(0.4) :
                        Double(item.drinks) > avgDrinks ? AppColors.accent : AppColors.accentDim
                    )
                    .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel {
                        if let s = val.as(String.self) {
                            Text(s)
                                .font(.system(size: 8))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { val in
                    AxisGridLine().foregroundStyle(AppColors.border.opacity(0.4))
                    AxisValueLabel {
                        if let i = val.as(Int.self) {
                            Text("\(i)")
                                .font(.system(size: 9))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 140)
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .padding(.horizontal)
    }
}

// MARK: - Day of Week Card

private struct DayOfWeekCard: View {
    let data: [DayBucket]

    private var maxAvg: Double { data.map(\.avgDrinks).max() ?? 1 }
    private var topDay: String? { data.max(by: { $0.avgDrinks < $1.avgDrinks })?.day }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("YOUR TYPICAL WEEK")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                if let top = topDay {
                    Text("\(top)s are your biggest night")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data) { item in
                    let fraction = maxAvg > 0 ? item.avgDrinks / maxAvg : 0
                    let isTop    = item.day == topDay && item.nights > 0
                    VStack(spacing: 5) {
                        if item.nights > 0 {
                            Text(String(format: "%.1f", item.avgDrinks))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(isTop ? AppColors.accent : AppColors.textSecondary)
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                isTop ? AppColors.accent :
                                item.nights > 0 ? AppColors.accentDim.opacity(0.75) :
                                AppColors.border.opacity(0.3)
                            )
                            .frame(height: max(CGFloat(fraction) * 80, item.nights > 0 ? 4 : 2))
                            .frame(maxWidth: .infinity)
                        Text(item.day)
                            .font(.system(size: 10))
                            .foregroundStyle(isTop ? AppColors.accent : AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112)

            Text("Avg drinks per night out, by day of week")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .padding(.horizontal)
    }
}

// MARK: - Monthly

private struct MonthlyView: View {
    let stats: MonthlyStats
    @Binding var offset: Int

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        let date = Calendar.current.date(byAdding: .month, value: offset, to: Date())!
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { offset -= 1 } label: {
                    Image(systemName: "chevron.left").foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Spacer()
                Button { if offset < 0 { offset += 1 } } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(offset < 0 ? AppColors.textSecondary : AppColors.textTertiary)
                }
                .disabled(offset >= 0)
            }
            .padding(.horizontal)

            if stats.totalEvents == 0 {
                VStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("No nights this month")
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(value: "\(stats.totalEvents)",  label: "Nights",    icon: "moon.fill")
                    StatCard(value: "\(stats.totalDrinks)",  label: "Drinks",    icon: "wineglass.fill")
                    StatCard(value: String(format: "%.1f", stats.avgDrinksPerNight), label: "Avg / Night", icon: "chart.bar.fill")
                    StatCard(value: "\(Int(stats.totalCalories))", label: "Calories", icon: "flame.fill")
                }
                .padding(.horizontal)

                if let record = stats.recordNight {
                    RecordCard(title: "Best Night", name: record.name, date: record.date, count: record.total)
                }

                if !stats.drinksByType.isEmpty {
                    DrinksByTypeCard(items: stats.drinksByType)
                }
            }

            Color.clear.frame(height: 32)
        }
        .padding(.top)
    }
}

// MARK: - Drinks By Type Chart

private struct DrinksByTypeCard: View {
    let items: [(name: String, count: Int)]

    private var maxCount: Int { items.map(\.count).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BY TYPE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: 10) {
                ForEach(items.prefix(6), id: \.name) { item in
                    HStack(spacing: 10) {
                        Text(item.name)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.text)
                            .frame(width: 80, alignment: .leading)

                        GeometryReader { geo in
                            let fraction = CGFloat(item.count) / CGFloat(maxCount)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppColors.border.opacity(0.3))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppColors.accent)
                                    .frame(width: geo.size.width * fraction)
                            }
                        }
                        .frame(height: 8)

                        Text("×\(item.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .padding(.horizontal)
    }
}

// MARK: - Shared Cards

private struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppColors.accent)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.text)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppColors.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }
}

private struct RecordCard: View {
    let title: String
    let name: String
    let date: Date
    let count: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                Text("drinks")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .padding(.horizontal)
    }
}

private struct StreakCard: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(value > 0 ? AppColors.accent : AppColors.textTertiary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(AppColors.surface)
        .cornerRadius(14)
    }
}
