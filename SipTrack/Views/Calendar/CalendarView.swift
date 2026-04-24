import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var appState: AppState
    @State private var displayMonth = Date()
    @State private var selectedDay: Date? = nil

    private let cal = Calendar.current
    private let weekdaySymbols = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]

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
        var days: [Date?] = Array(repeating: nil, count: wd)
        for day in range {
            days.append(cal.date(byAdding: .day, value: day - 1, to: monthStart))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayMonth)
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
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Text(monthTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                        Spacer()
                        Button { changeMonth(1) } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .padding(.horizontal)

                    // Monthly summary
                    if !monthEvents.isEmpty {
                        HStack(spacing: 0) {
                            MonthStat(value: "\(monthEvents.count)", label: "Nights")
                            Divider().frame(height: 36).background(AppColors.border)
                            MonthStat(value: "\(monthEvents.reduce(0) { $0 + appState.totalDrinks(for: $1.id) })", label: "Drinks")
                            Divider().frame(height: 36).background(AppColors.border)
                            MonthStat(value: "\(Int(monthEvents.reduce(0.0) { $0 + appState.totalCalories(for: $1.id) }))", label: "Calories")
                        }
                        .padding(.vertical, 12)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Weekday headers
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                        ForEach(weekdaySymbols, id: \.self) { sym in
                            Text(sym)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .padding(.horizontal)

                    // Calendar grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                        ForEach(0..<days.count, id: \.self) { i in
                            if let day = days[i] {
                                DayCell(
                                    date: day,
                                    events: eventsOn(day),
                                    isSelected: selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false,
                                    isToday: cal.isDateInToday(day)
                                )
                                .onTapGesture {
                                    selectedDay = cal.isDate(day, inSameDayAs: selectedDay ?? .distantPast) ? nil : day
                                }
                            } else {
                                Color.clear
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Selected day detail
                    if let selected = selectedDay {
                        let dayEvents = eventsOn(selected)
                        if !dayEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(dayTitle(selected))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                                ForEach(dayEvents) { event in
                                    NavigationLink(value: Route.summary(event.id)) {
                                        EventRow(event: event, drinkCount: appState.totalDrinks(for: event.id))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

                    // Legend
                    HStack(spacing: 16) {
                        LegendDot(color: AppColors.accentDim, label: "1-2 drinks")
                        LegendDot(color: AppColors.accent.opacity(0.5), label: "3-5 drinks")
                        LegendDot(color: AppColors.accent, label: "6+ drinks")
                    }
                    .padding(.horizontal)
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

private struct DayCell: View {
    let date: Date
    let events: [NightEvent]
    let isSelected: Bool
    let isToday: Bool
    @EnvironmentObject var appState: AppState

    private var drinkTotal: Int { events.reduce(0) { $0 + appState.totalDrinks(for: $1.id) } }

    private var intensity: Color {
        switch drinkTotal {
        case 0:     return Color.clear
        case 1...2: return AppColors.accentDim
        case 3...5: return AppColors.accent.opacity(0.5)
        default:    return AppColors.accent
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? AppColors.accent : intensity)
            if isToday && !isSelected {
                Circle()
                    .stroke(AppColors.accent, lineWidth: 1.5)
            }
            VStack(spacing: 1) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? .black : (drinkTotal > 0 ? AppColors.text : AppColors.textSecondary))
                if events.contains(where: { $0.notes?.isEmpty == false }) {
                    Circle()
                        .fill(isSelected ? Color.black.opacity(0.5) : AppColors.accent)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct MonthStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.text)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
        }
    }
}

private struct EventRow: View {
    let event: NightEvent
    let drinkCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.text)
            }
            Spacer()
            Text("\(drinkCount) drinks")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.accent)
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(12)
        .background(AppColors.surface)
        .cornerRadius(10)
    }
}
