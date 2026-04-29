import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var appState: AppState
    @State private var displayMonth = Date()
    @State private var selectedDay: Date? = nil

    private let cal = Calendar.current
    private let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var monthEvents: [NightEvent] {
        let comps = cal.dateComponents([.year, .month], from: displayMonth)
        return appState.visibleEvents.filter {
            let c = cal.dateComponents([.year, .month], from: $0.startTime)
            return c.year == comps.year && c.month == comps.month
        }
    }

    private var days: [Date?] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayMonth)),
              let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        var wd = cal.component(.weekday, from: monthStart) - 2
        if wd < 0 { wd += 7 }
        var result: [Date?] = Array(repeating: nil, count: wd)
        for day in range {
            result.append(cal.date(byAdding: .day, value: day - 1, to: monthStart))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayMonth)
    }

    private var monthAvgPeakBAC: Double? {
        let bacs = monthEvents.map { peakBAC(for: $0) }.filter { $0 > 0 }
        guard !bacs.isEmpty else { return nil }
        return bacs.reduce(0, +) / Double(bacs.count)
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    // Month navigator
                    HStack {
                        Button { changeMonth(-1) } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                        Spacer()
                        Text(monthTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                        Spacer()
                        Button { changeMonth(1) } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal)

                    // Monthly summary
                    if !monthEvents.isEmpty {
                        let totalDrinks = monthEvents.reduce(0) { $0 + appState.totalDrinks(for: $1.id) }
                        let totalCal    = Int(monthEvents.reduce(0.0) { $0 + appState.totalCalories(for: $1.id) })
                        HStack(spacing: 0) {
                            CalMonthStat(value: "\(monthEvents.count)", label: "Nights")
                            Rectangle().fill(AppColors.border).frame(width: 1, height: 32)
                            CalMonthStat(value: "\(totalDrinks)", label: "Drinks")
                            Rectangle().fill(AppColors.border).frame(width: 1, height: 32)
                            CalMonthStat(value: "\(totalCal)", label: "Calories")
                            if let avg = monthAvgPeakBAC {
                                Rectangle().fill(AppColors.border).frame(width: 1, height: 32)
                                CalMonthStat(
                                    value: String(format: "%.3f", avg),
                                    label: "Avg Peak",
                                    valueColor: IntoxicationStage.stage(for: avg).color
                                )
                            }
                        }
                        .padding(.vertical, 12)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                        .padding(.horizontal)
                    }

                    // Weekday headers
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                        ForEach(weekdaySymbols, id: \.self) { sym in
                            Text(sym)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .padding(.horizontal)

                    // Calendar grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                        ForEach(0..<days.count, id: \.self) { i in
                            if let day = days[i] {
                                let events = eventsOn(day)
                                let bac = events.isEmpty ? nil : events.map { peakBAC(for: $0) }.max()
                                CalDayCell(
                                    date: day,
                                    hasEvents: !events.isEmpty,
                                    peakBAC: bac,
                                    isSelected: selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false,
                                    isToday: cal.isDateInToday(day)
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        let alreadySelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
                                        selectedDay = alreadySelected ? nil : day
                                    }
                                }
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Selected day detail
                    if let selected = selectedDay {
                        let dayEvents = eventsOn(selected)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(dayTitle(selected))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.horizontal)

                            if dayEvents.isEmpty {
                                Text("No nights recorded this day.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.textTertiary)
                                    .padding(.horizontal)
                            } else {
                                ForEach(dayEvents) { event in
                                    let bac   = peakBAC(for: event)
                                    let stage = IntoxicationStage.stage(for: bac)
                                    NavigationLink(value: Route.summary(event.id)) {
                                        CalEventRow(
                                            event: event,
                                            drinkCount: appState.totalDrinks(for: event.id),
                                            calories:   Int(appState.totalCalories(for: event.id)),
                                            peakBAC:    bac,
                                            stageColor: stage.color,
                                            stageName:  stage.name
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Stage legend
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PEAK BAC COLOR")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(AppColors.textTertiary)
                        HStack(spacing: 12) {
                            ForEach(IntoxicationStage.all.prefix(5), id: \.name) { stage in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(stage.color.opacity(0.85))
                                        .frame(width: 9, height: 9)
                                    Text(stage.name)
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top)
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.2), value: selectedDay)
    }

    private func eventsOn(_ date: Date) -> [NightEvent] {
        appState.visibleEvents.filter { cal.isDate($0.startTime, inSameDayAs: date) }
    }

    private func peakBAC(for event: NightEvent) -> Double {
        let entries = appState.entries.filter { $0.eventId == event.id }
        let r = BACCalculator.profileR(profile: appState.userProfile)
        return BACCalculator.estimatePeakBAC(
            entries: entries,
            drinkTypes: appState.allDrinkTypes,
            weightKg: appState.userProfile.weightKg,
            sex: appState.userProfile.sex,
            eventStart: event.startTime,
            r: r
        )
    }

    private func changeMonth(_ delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: displayMonth) {
            displayMonth = next
        }
    }

    private func dayTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }
}

// MARK: - Subviews

private struct CalDayCell: View {
    let date: Date
    let hasEvents: Bool
    let peakBAC: Double?
    let isSelected: Bool
    let isToday: Bool

    private var stageColor: Color {
        guard let bac = peakBAC, bac > 0 else { return .clear }
        return IntoxicationStage.stage(for: bac).color
    }

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(AppColors.accent)
            } else if hasEvents {
                Circle().fill(stageColor.opacity(0.85))
            }
            if isToday && !isSelected {
                Circle().stroke(AppColors.accent, lineWidth: 1.5)
            }
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                .foregroundStyle(
                    isSelected ? .black :
                    hasEvents  ? .white :
                    AppColors.textSecondary
                )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct CalMonthStat: View {
    let value: String
    let label: String
    var valueColor: Color = AppColors.text

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CalEventRow: View {
    let event: NightEvent
    let drinkCount: Int
    let calories: Int
    let peakBAC: Double
    let stageColor: Color
    let stageName: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(stageColor)
                .frame(width: 4, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.text)
                HStack(spacing: 6) {
                    Text("\(drinkCount) drinks")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("·")
                        .foregroundStyle(AppColors.textTertiary)
                    Text("\(calories) cal")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.3f%%", peakBAC))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(stageColor)
                Text(stageName)
                    .font(.system(size: 10))
                    .foregroundStyle(stageColor.opacity(0.7))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(12)
        .background(AppColors.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stageColor.opacity(0.3), lineWidth: 1))
    }
}
