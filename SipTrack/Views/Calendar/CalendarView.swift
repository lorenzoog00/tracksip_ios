import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var appState: AppState
    @State private var displayMonth = Date()
    @State private var selectedDay: Date? = nil
    @State private var showPaywall = false

    private let cal = Calendar.current
    private let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

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

    private var monthName: String {
        let f = DateFormatter(); f.dateFormat = "MMMM"
        return f.string(from: displayMonth).uppercased()
    }

    private var yearString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy"
        return f.string(from: displayMonth)
    }

    private var monthAvgPeakBAC: Double? {
        let bacs = monthEvents.map { peakBAC(for: $0) }.filter { $0 > 0 }
        guard !bacs.isEmpty else { return nil }
        return bacs.reduce(0, +) / Double(bacs.count)
    }

    var body: some View {
        Group {
            if appState.isPro {
                calendarContent
            } else {
                calendarPaywall
            }
        }
        .sheet(isPresented: $showPaywall) { ProView(presentation: .modal) }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calendarPaywall: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(AppColors.accent.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.accent)
                }

                VStack(spacing: 8) {
                    Text("Calendar Heatmap")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    Text("See every night mapped on a calendar with BAC colour coding, monthly stats, and trend history.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button { showPaywall = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13))
                        Text("Unlock with Pro")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [AppColors.accentWarm, AppColors.accent],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                    .shadow(color: AppColors.accent.opacity(0.45), radius: 12, y: 5)
                }
                .padding(.horizontal, 32)
                Spacer()
            }
        }
    }

    private var calendarContent: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            // Ambient top glow
            VStack {
                RadialGradient(
                    colors: [AppColors.accent.opacity(0.09), Color.clear],
                    center: .center, startRadius: 0, endRadius: 240
                )
                .frame(height: 320)
                .offset(y: -60)
                Spacer()
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // MARK: — Month Header
                    HStack(alignment: .center, spacing: 0) {
                        Button { changeMonth(-1) } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .ultraLight))
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(width: 44, height: 68)
                                .contentShape(Rectangle())
                        }

                        VStack(spacing: 4) {
                            Text(monthName)
                                .font(.system(size: 28, weight: .black))
                                .tracking(8)
                                .foregroundStyle(AppColors.text)

                            Text(yearString)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(5)
                                .foregroundStyle(AppColors.accent.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)

                        Button { changeMonth(1) } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .ultraLight))
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(width: 44, height: 68)
                                .contentShape(Rectangle())
                        }
                    }
                    .padding(.top, 6)

                    // Gold rule
                    LinearGradient(
                        colors: [Color.clear, AppColors.accent.opacity(0.45), Color.clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 1)
                    .padding(.horizontal, 48)
                    .padding(.top, 6)
                    .padding(.bottom, 22)

                    // MARK: — Monthly Stats Strip
                    if !monthEvents.isEmpty {
                        let totalDrinks = monthEvents.reduce(0) { $0 + appState.totalDrinks(for: $1.id) }
                        let totalCal    = Int(monthEvents.reduce(0.0) { $0 + appState.totalCalories(for: $1.id) })

                        HStack(spacing: 0) {
                            CalStatPill(value: "\(monthEvents.count)", label: "NIGHTS")
                            CalStatDivider()
                            CalStatPill(value: "\(totalDrinks)", label: "DRINKS")
                            CalStatDivider()
                            CalStatPill(value: "\(totalCal)", label: "CALS")
                            if let avg = monthAvgPeakBAC {
                                CalStatDivider()
                                CalStatPill(
                                    value: String(format: "%.3f", avg),
                                    label: "AVG BAC",
                                    valueColor: IntoxicationStage.stage(for: avg).color
                                )
                            }
                        }
                        .padding(.vertical, 16)
                        .premiumCard(radius: 16, tint: AppColors.accent, tintOpacity: 0.025)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }

                    // MARK: — Weekday Headers
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                        ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { idx, sym in
                            Text(sym)
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(
                                    (idx == 5 || idx == 6)
                                        ? AppColors.accent.opacity(0.45)
                                        : AppColors.textTertiary
                                )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    // MARK: — Calendar Grid
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
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
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

                    // MARK: — Selected Day Detail
                    if let selected = selectedDay {
                        let dayEvents = eventsOn(selected)

                        VStack(alignment: .leading, spacing: 0) {
                            // Day header
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dayName(selected).uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(3)
                                        .foregroundStyle(AppColors.accent.opacity(0.65))

                                    HStack(alignment: .lastTextBaseline, spacing: 7) {
                                        Text(dayNumber(selected))
                                            .font(.system(size: 40, weight: .black))
                                            .foregroundStyle(AppColors.text)
                                        Text(monthAbbrev(selected))
                                            .font(.system(size: 13, weight: .semibold))
                                            .tracking(2)
                                            .foregroundStyle(AppColors.textTertiary)
                                            .padding(.bottom, 4)
                                    }
                                }

                                Spacer()

                                if !dayEvents.isEmpty {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(dayEvents.count)")
                                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                                            .foregroundStyle(AppColors.accent)
                                        Text(dayEvents.count == 1 ? "NIGHT" : "NIGHTS")
                                            .font(.system(size: 8, weight: .bold))
                                            .tracking(2)
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 18)

                            // Divider
                            LinearGradient(
                                colors: [Color.clear, AppColors.border.opacity(0.6), Color.clear],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(height: 1)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)

                            // Events or empty
                            if dayEvents.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("No nights recorded")
                                        .font(.system(size: 13))
                                        .foregroundStyle(AppColors.textTertiary)
                                        .italic()
                                    Spacer()
                                }
                                .padding(.bottom, 18)
                            } else {
                                VStack(spacing: 4) {
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
                                        .padding(.horizontal, 12)
                                    }
                                }
                                .padding(.bottom, 12)
                            }
                        }
                        .background(
                            ZStack {
                                LinearGradient(
                                    colors: [AppColors.surfaceTop, AppColors.surfaceBottom],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                                AppColors.accent.opacity(0.025)
                            }
                        )
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [AppColors.rimLight, AppColors.border.opacity(0.55)],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .padding(.horizontal)
                        .padding(.top, 20)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    // MARK: — BAC Scale Legend
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BAC SCALE")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(AppColors.textTertiary)

                        LinearGradient(
                            colors: IntoxicationStage.all.prefix(6).map { $0.color },
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(height: 3)
                        .cornerRadius(1.5)

                        HStack(spacing: 0) {
                            ForEach(IntoxicationStage.all.prefix(6), id: \.name) { stage in
                                Text(stage.name)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(stage.color.opacity(0.65))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 32)
                    .padding(.bottom, 40)
                }
                .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: selectedDay)
        .animation(.easeInOut(duration: 0.18), value: displayMonth)
    }

    // MARK: - Helpers

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

    private func dayName(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: date)
    }

    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }

    private func monthAbbrev(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: date)
    }
}

// MARK: - CalDayCell

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
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.accent)
                    .shadow(color: AppColors.accent.opacity(0.55), radius: 7, x: 0, y: 3)
            } else if hasEvents {
                RoundedRectangle(cornerRadius: 8)
                    .fill(stageColor.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(stageColor.opacity(0.5), lineWidth: 0.75)
                    )
            }

            if isToday && !isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.accent, lineWidth: 1.5)
            }

            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 13, weight: isSelected || isToday ? .bold : .regular))
                    .foregroundStyle(
                        isSelected ? Color.black :
                        hasEvents  ? stageColor  :
                        isToday    ? AppColors.accent :
                        AppColors.textSecondary
                    )

                if hasEvents && !isSelected {
                    Circle()
                        .fill(stageColor)
                        .frame(width: 3, height: 3)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(isSelected ? 1.06 : 1.0)
    }
}

// MARK: - CalStatPill

private struct CalStatPill: View {
    let value: String
    let label: String
    var valueColor: Color = AppColors.text

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .tracking(2)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CalStatDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.border.opacity(0.6))
            .frame(width: 1, height: 26)
    }
}

// MARK: - CalEventRow

private struct CalEventRow: View {
    let event: NightEvent
    let drinkCount: Int
    let calories: Int
    let peakBAC: Double
    let stageColor: Color
    let stageName: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [stageColor, stageColor.opacity(0.35)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                HStack(spacing: 6) {
                    Text("\(drinkCount) drinks")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("·").foregroundStyle(AppColors.textTertiary)
                    Text("\(calories) cal")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.3f%%", peakBAC))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(stageColor)
                Text(stageName.uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(stageColor.opacity(0.6))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }
}
