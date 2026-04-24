import SwiftUI

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
        let comps = Calendar.current.dateComponents([.year, .month],
            from: Calendar.current.date(byAdding: .month, value: monthOffset, to: Date())!)
        return AnalyticsEngine.monthly(
            year: comps.year!,
            month: comps.month!,
            events: appState.events,
            entries: appState.entries,
            drinkTypes: appState.allDrinkTypes
        )
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("Tab", selection: $tab) {
                    Text("All Time").tag(0)
                    Text("Monthly").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                ScrollView {
                    if tab == 0 {
                        AllTimeView(stats: allTime)
                    } else {
                        MonthlyView(stats: monthly, offset: $monthOffset)
                    }
                }
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AllTimeView: View {
    let stats: AllTimeStats

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

            if !stats.insights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Insights", systemImage: "lightbulb.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                    ForEach(stats.insights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(AppColors.accent)
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
            // Month selector
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
                Text("No nights this month")
                    .foregroundStyle(AppColors.textSecondary)
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("By Type")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                        ForEach(stats.drinksByType.prefix(5), id: \.name) { item in
                            HStack {
                                Text(item.name)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.text)
                                Spacer()
                                Text("×\(item.count)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                    .padding()
                    .background(AppColors.surface)
                    .cornerRadius(14)
                    .padding(.horizontal)
                }
            }

            Color.clear.frame(height: 32)
        }
        .padding(.top)
    }
}

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
