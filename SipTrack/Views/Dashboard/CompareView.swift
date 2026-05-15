import SwiftUI
import Charts

// MARK: - Period preset

enum ComparePeriod: String, CaseIterable, Identifiable {
    case thisWeek  = "This Week"
    case lastWeek  = "Last Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case last3M    = "Last 3 Months"

    var id: String { rawValue }

    var dateRange: (from: Date, to: Date) {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .thisWeek:
            let s = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            return (s, now)
        case .lastWeek:
            let s0 = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            let s1 = cal.date(byAdding: .weekOfYear, value: -1, to: s0) ?? now
            return (s1, s0)
        case .thisMonth:
            let s = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            return (s, now)
        case .lastMonth:
            let s0 = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let s1 = cal.date(byAdding: .month, value: -1, to: s0) ?? now
            return (s1, s0)
        case .last3M:
            return (cal.date(byAdding: .month, value: -3, to: now) ?? now, now)
        }
    }
}

// MARK: - Root

struct CompareView: View {
    @EnvironmentObject var appState: AppState
    @State private var periodA: ComparePeriod = .lastMonth
    @State private var periodB: ComparePeriod = .thisMonth

    private var statsA: PeriodStats {
        let r = periodA.dateRange
        return AnalyticsEngine.period(
            from: r.from, to: r.to, label: periodA.rawValue,
            events: appState.events, entries: appState.entries,
            drinkTypes: appState.allDrinkTypes, profile: appState.userProfile
        )
    }

    private var statsB: PeriodStats {
        let r = periodB.dateRange
        return AnalyticsEngine.period(
            from: r.from, to: r.to, label: periodB.rawValue,
            events: appState.events, entries: appState.entries,
            drinkTypes: appState.allDrinkTypes, profile: appState.userProfile
        )
    }

    var body: some View {
        if !appState.isPro {
            CompareLockedView()
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        PeriodPickerButton(slotLabel: "A", color: AppColors.accent, selected: $periodA)
                        PeriodPickerButton(slotLabel: "B", color: AppColors.water, selected: $periodB)
                    }
                    .padding(.horizontal)

                    CompareHeroCard(a: statsA, b: statsB)
                    CompareStatsCard(a: statsA, b: statsB)

                    if statsA.totalEvents > 0 || statsB.totalEvents > 0 {
                        DayOfWeekCompareCard(a: statsA, b: statsB)
                    }

                    Color.clear.frame(height: 32)
                }
                .padding(.top)
            }
        }
    }
}

// MARK: - Period picker button

private struct PeriodPickerButton: View {
    let slotLabel: String
    let color: Color
    @Binding var selected: ComparePeriod

    var body: some View {
        Menu {
            ForEach(ComparePeriod.allCases) { period in
                Button {
                    selected = period
                } label: {
                    if selected == period {
                        Label(period.rawValue, systemImage: "checkmark")
                    } else {
                        Text(period.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.18))
                        .frame(width: 24, height: 24)
                    Text(slotLabel)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(color)
                }
                Text(selected.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [AppColors.surfaceTop, AppColors.surfaceBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                    color.opacity(0.07)
                }
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.45), AppColors.border.opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Hero card

private struct CompareHeroCard: View {
    let a: PeriodStats
    let b: PeriodStats

    private var delta: Double { b.avgDrinksPerNight - a.avgDrinksPerNight }

    private var pct: Double {
        guard a.avgDrinksPerNight > 0 else { return 0 }
        return abs(delta) / a.avgDrinksPerNight * 100
    }

    private var headline: String {
        guard a.totalEvents > 0 || b.totalEvents > 0 else { return "No data yet — start tracking!" }
        if abs(delta) < 0.05 { return "Same pace both periods" }
        let dir = delta < 0 ? "lighter" : "heavier"
        return String(format: "%.0f%% %@ in Period B", pct, dir)
    }

    private var headlineColor: Color {
        guard abs(delta) >= 0.05 else { return AppColors.textSecondary }
        return delta < 0 ? AppColors.success : AppColors.danger
    }

    private var headlineIcon: String {
        guard abs(delta) >= 0.05 else { return "equal.circle.fill" }
        return delta < 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Circle().fill(AppColors.accent).frame(width: 7, height: 7)
                        Text(a.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(a.totalEvents == 0 ? "—" : String(format: "%.1f", a.avgDrinksPerNight))
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(AppColors.accent)
                        .minimumScaleFactor(0.6)
                    Text("avg / night")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    Spacer().frame(height: 34)
                    Text("vs")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Circle().fill(AppColors.water).frame(width: 7, height: 7)
                        Text(b.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(b.totalEvents == 0 ? "—" : String(format: "%.1f", b.avgDrinksPerNight))
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(AppColors.water)
                        .minimumScaleFactor(0.6)
                    Text("avg / night")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 6) {
                Image(systemName: headlineIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(headlineColor)
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(headlineColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(headlineColor.opacity(0.1))
            .cornerRadius(20)
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [AppColors.surfaceTop, AppColors.surfaceBottom],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [AppColors.accent.opacity(0.14), .clear],
                    center: UnitPoint(x: 0.18, y: 0.45),
                    startRadius: 0, endRadius: 130
                )
                RadialGradient(
                    colors: [AppColors.water.opacity(0.14), .clear],
                    center: UnitPoint(x: 0.82, y: 0.45),
                    startRadius: 0, endRadius: 130
                )
            }
        )
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [AppColors.rimLight, AppColors.border.opacity(0.8)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .padding(.horizontal)
    }
}

// MARK: - Stats comparison table

private struct CompareStatsCard: View {
    let a: PeriodStats
    let b: PeriodStats

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BREAKDOWN")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.accent).frame(width: 6, height: 6)
                        Text("A")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.water).frame(width: 6, height: 6)
                        Text("B")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.water)
                    }
                    Text("Δ")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle().fill(AppColors.border.opacity(0.6)).frame(height: 1)

            CompareRow(
                icon: "moon.fill", label: "Nights",
                aVal: "\(a.totalEvents)", bVal: "\(b.totalEvents)",
                delta: Double(b.totalEvents - a.totalEvents), lessIsBetter: false
            )
            Rectangle().fill(AppColors.border.opacity(0.25)).frame(height: 1).padding(.leading, 48)

            CompareRow(
                icon: "wineglass.fill", label: "Total Drinks",
                aVal: "\(a.totalDrinks)", bVal: "\(b.totalDrinks)",
                delta: Double(b.totalDrinks - a.totalDrinks), lessIsBetter: true
            )
            Rectangle().fill(AppColors.border.opacity(0.25)).frame(height: 1).padding(.leading, 48)

            CompareRow(
                icon: "chart.bar.fill", label: "Avg / Night",
                aVal: a.totalEvents == 0 ? "—" : String(format: "%.1f", a.avgDrinksPerNight),
                bVal: b.totalEvents == 0 ? "—" : String(format: "%.1f", b.avgDrinksPerNight),
                delta: b.avgDrinksPerNight - a.avgDrinksPerNight, lessIsBetter: true
            )
            Rectangle().fill(AppColors.border.opacity(0.25)).frame(height: 1).padding(.leading, 48)

            CompareRow(
                icon: "flame.fill", label: "Calories",
                aVal: "\(Int(a.totalCalories))", bVal: "\(Int(b.totalCalories))",
                delta: b.totalCalories - a.totalCalories, lessIsBetter: true
            )
            Rectangle().fill(AppColors.border.opacity(0.25)).frame(height: 1).padding(.leading, 48)

            CompareRow(
                icon: "flask.fill", label: "Alcohol",
                aVal: "\(Int(a.totalAlcoholG))g", bVal: "\(Int(b.totalAlcoholG))g",
                delta: b.totalAlcoholG - a.totalAlcoholG, lessIsBetter: true
            )
            Rectangle().fill(AppColors.border.opacity(0.25)).frame(height: 1).padding(.leading, 48)

            CompareRow(
                icon: "waveform.path.ecg", label: "Avg Mean BAC",
                aVal: a.avgMeanBAC > 0 ? String(format: "%.3f%%", a.avgMeanBAC) : "—",
                bVal: b.avgMeanBAC > 0 ? String(format: "%.3f%%", b.avgMeanBAC) : "—",
                delta: b.avgMeanBAC - a.avgMeanBAC, lessIsBetter: true
            )
        }
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .padding(.horizontal)
    }
}

private struct CompareRow: View {
    let icon: String
    let label: String
    let aVal: String
    let bVal: String
    let delta: Double
    let lessIsBetter: Bool

    private var isNeutral: Bool { abs(delta) < 0.05 }
    private var bIsLess: Bool { delta < 0 }

    private var deltaColor: Color {
        if isNeutral { return AppColors.textTertiary }
        if !lessIsBetter { return AppColors.textSecondary }
        return bIsLess ? AppColors.success : AppColors.danger
    }

    private var deltaBadge: String {
        if isNeutral { return "=" }
        let abs = Swift.abs(delta)
        let arrow = bIsLess ? "↓" : "↑"
        if abs == Double(Int(abs)) { return "\(arrow) \(Int(abs))" }
        return "\(arrow) \(String(format: "%.1f", abs))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.text)
            Spacer()
            Text(aVal)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 52, alignment: .trailing)
            Text(bVal)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppColors.water)
                .frame(width: 52, alignment: .trailing)
            Text(deltaBadge)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(deltaColor)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: - Day of week grouped chart

private struct DayOfWeekCompareCard: View {
    let a: PeriodStats
    let b: PeriodStats

    private struct BarData: Identifiable {
        let id = UUID()
        let day: String
        let period: String
        let value: Double
    }

    private let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var bars: [BarData] {
        dayOrder.flatMap { day in [
            BarData(day: day, period: "A", value: a.dayOfWeekAvg[day] ?? 0),
            BarData(day: day, period: "B", value: b.dayOfWeekAvg[day] ?? 0)
        ]}
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BY DAY OF WEEK")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text("avg drinks")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }

            Chart {
                ForEach(bars) { bar in
                    BarMark(
                        x: .value("Day", bar.day),
                        y: .value("Drinks", bar.value)
                    )
                    .foregroundStyle(by: .value("Period", bar.period))
                    .cornerRadius(4)
                }
            }
            .chartForegroundStyleScale(["A": AppColors.accent, "B": AppColors.water])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel {
                        if let s = val.as(String.self) {
                            Text(s)
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { val in
                    AxisGridLine().foregroundStyle(AppColors.border.opacity(0.4))
                    AxisValueLabel {
                        if let n = val.as(Double.self) {
                            Text(String(format: "%.1f", n))
                                .font(.system(size: 9))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 150)

            HStack(spacing: 16) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(AppColors.accent).frame(width: 12, height: 10)
                    Text(a.label).font(.system(size: 11)).foregroundStyle(AppColors.textTertiary)
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(AppColors.water).frame(width: 12, height: 10)
                    Text(b.label).font(.system(size: 11)).foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .padding(.horizontal)
    }
}

// MARK: - Locked / paywall state

private struct CompareLockedView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(AppColors.accent.opacity(0.08))
                        .frame(width: 100, height: 100)
                        .blur(radius: 12)
                    Circle()
                        .fill(AppColors.accent.opacity(0.07))
                        .frame(width: 76, height: 76)
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.accent)
                }

                VStack(spacing: 10) {
                    Text("Compare Periods")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    Text("Track your progress over time.\nCompare drinks, calories and alcohol\nbetween any two periods.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                HStack(spacing: 8) {
                    FeaturePill(icon: "moon.fill",        text: "Nights")
                    FeaturePill(icon: "wineglass.fill",   text: "Drinks")
                    FeaturePill(icon: "flame.fill",       text: "Calories")
                }

                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill").font(.system(size: 14))
                        Text("Unlock with Premium")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.accent)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 8)
            }
            .padding(28)
            .background(AppColors.surface)
            .cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppColors.border, lineWidth: 1))
            .padding(.horizontal, 24)
            Spacer()
        }
        .sheet(isPresented: $showPaywall) {
            ProView(presentation: .modal)
        }
    }
}

private struct FeaturePill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.accent)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(AppColors.accentDim)
        .cornerRadius(20)
    }
}
