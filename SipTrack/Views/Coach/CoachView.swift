import SwiftUI

// MARK: - Main Coach View

struct CoachView: View {
    @EnvironmentObject var appState: AppState

    enum CoachTab: Int, CaseIterable {
        case weekly, monthly, comparison
        var label: String {
            switch self {
            case .weekly:     return "WEEKLY"
            case .monthly:    return "MONTHLY"
            case .comparison: return "A VS B"
            }
        }
    }

    @State private var selectedTab: CoachTab = .weekly
    @State private var showNewComparison = false
    @State private var showTestMenu = false

    private var weeklyReports: [CoachReport] {
        appState.coachReports.filter { $0.type == .weekly }.sorted { $0.createdAt > $1.createdAt }
    }
    private var monthlyReports: [CoachReport] {
        appState.coachReports.filter { $0.type == .monthly }.sorted { $0.createdAt > $1.createdAt }
    }
    private var comparisonReports: [CoachReport] {
        appState.coachReports.filter { $0.type == .comparison }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            LinearGradient(
                colors: [AppColors.accent.opacity(0.05), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.28)
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                coachHeader
                tabBar

                Group {
                    switch selectedTab {
                    case .weekly:     weeklyContent
                    case .monthly:    monthlyContent
                    case .comparison: comparisonContent
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: selectedTab)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showNewComparison) {
            NewComparisonSheet()
        }
    }

    // MARK: - Header

    private var coachHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                    Text("AI COACH")
                        .font(.system(size: 11, weight: .black))
                        .tracking(3)
                        .foregroundStyle(AppColors.accent)
                }
                Text("HEALTH INTELLIGENCE")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.text)
            }
            Spacer()
            HStack(spacing: 10) {
                Button {
                    showTestMenu = true
                } label: {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .confirmationDialog("Generate Test Report", isPresented: $showTestMenu) {
                    Button("Test Weekly (this week)") { appState.generateTestWeeklyReport() }
                    Button("Test Monthly (this month)") { appState.generateTestMonthlyReport() }
                    Button("Cancel", role: .cancel) {}
                }
                Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .cornerRadius(9)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(CoachTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.label)
                            .font(.system(size: 11, weight: selectedTab == tab ? .black : .medium))
                            .tracking(1.8)
                            .foregroundStyle(selectedTab == tab ? AppColors.accent : AppColors.textTertiary)
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)
                        Rectangle()
                            .fill(selectedTab == tab ? AppColors.accent : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColors.border.opacity(0.4)).frame(height: 1)
        }
    }

    // MARK: - Weekly Tab

    private var weeklyContent: some View {
        Group {
            if weeklyReports.isEmpty {
                coachEmptyState(
                    icon: "calendar.badge.clock",
                    title: "NO WEEKLY REPORTS",
                    message: "Reports generate automatically\nafter each week with nights out."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(weeklyReports) { report in
                            CoachReportCard(report: report, periodLabel: weeklyLabel(report))
                                .padding(.horizontal, 16)
                                .contextMenu {
                                    if appState.generatingCoachReportId == report.id {
                                        Button(role: .destructive) {
                                            appState.cancelCoachReport(id: report.id)
                                        } label: {
                                            Label("Cancel", systemImage: "xmark.circle")
                                        }
                                    } else {
                                        Button(role: .destructive) {
                                            appState.deleteCoachReport(id: report.id)
                                        } label: {
                                            Label("Delete Report", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func weeklyLabel(_ report: CoachReport) -> String {
        let cal = Calendar(identifier: .iso8601)
        let weekNum = cal.component(.weekOfYear, from: report.periodStart)
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        let start = fmt.string(from: report.periodStart)
        let endDate = cal.date(byAdding: .day, value: -1, to: report.periodEnd) ?? report.periodEnd
        return "WK \(weekNum) • \(start)–\(fmt.string(from: endDate))"
    }

    // MARK: - Monthly Tab

    private var monthlyContent: some View {
        Group {
            if monthlyReports.isEmpty {
                coachEmptyState(
                    icon: "chart.bar.doc.horizontal",
                    title: "NO MONTHLY REPORTS",
                    message: "Reports generate automatically\non the first day of each new month."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(monthlyReports) { report in
                            CoachReportCard(report: report, periodLabel: monthlyLabel(report))
                                .padding(.horizontal, 16)
                                .contextMenu {
                                    if appState.generatingCoachReportId == report.id {
                                        Button(role: .destructive) {
                                            appState.cancelCoachReport(id: report.id)
                                        } label: {
                                            Label("Cancel", systemImage: "xmark.circle")
                                        }
                                    } else {
                                        Button(role: .destructive) {
                                            appState.deleteCoachReport(id: report.id)
                                        } label: {
                                            Label("Delete Report", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func monthlyLabel(_ report: CoachReport) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: report.periodStart).uppercased()
    }

    // MARK: - A vs B Tab

    private var comparisonContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                newComparisonButton
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                if comparisonReports.isEmpty {
                    coachEmptyState(
                        icon: "arrow.triangle.branch",
                        title: "NO COMPARISONS YET",
                        message: "Pick two nights to see a\nside-by-side health analysis."
                    )
                    .frame(minHeight: 260)
                } else {
                    ForEach(comparisonReports) { report in
                        ComparisonReportCard(report: report)
                            .padding(.horizontal, 16)
                            .contextMenu {
                                if appState.generatingCoachReportId == report.id {
                                    Button(role: .destructive) {
                                        appState.cancelCoachReport(id: report.id)
                                    } label: {
                                        Label("Cancel", systemImage: "xmark.circle")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        appState.deleteCoachReport(id: report.id)
                                    } label: {
                                        Label("Delete Report", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    private var newComparisonButton: some View {
        Button { showNewComparison = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .semibold))
                Text("NEW COMPARISON")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1.5)
            }
            .foregroundStyle(AppColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.accentDim)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppColors.accent.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private func coachEmptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.07))
                    .frame(width: 80, height: 80)
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(AppColors.accent.opacity(0.5))
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundStyle(AppColors.textTertiary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - New Comparison Sheet

struct NewComparisonSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var eventAId: String? = nil
    @State private var eventBId: String? = nil

    private var pastEvents: [NightEvent] {
        appState.events.filter { $0.endTime != nil }.sorted { $0.startTime > $1.startTime }
    }
    private var canGenerate: Bool { eventAId != nil && eventBId != nil && eventAId != eventBId }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader
                selectionSlots
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                Rectangle()
                    .fill(AppColors.border.opacity(0.4))
                    .frame(height: 1)

                if pastEvents.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(AppColors.textTertiary)
                        Text("No past nights found")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(pastEvents) { event in
                                eventRow(event)
                                    .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, canGenerate ? 90 : 0)
                    }
                }
            }

            if canGenerate {
                generateButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: canGenerate)
            }
        }
    }

    // MARK: Sheet Header

    private var sheetHeader: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColors.border)
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 16)

            Text("COMPARE TWO NIGHTS")
                .font(.system(size: 14, weight: .black))
                .tracking(2.5)
                .foregroundStyle(AppColors.text)
            Text("Tap nights below to select A and B")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 4)
                .padding(.bottom, 16)

            Rectangle()
                .fill(AppColors.border.opacity(0.4))
                .frame(height: 1)
        }
    }

    // MARK: Selection Slots

    private var selectionSlots: some View {
        HStack(spacing: 12) {
            slot(label: "A", eventId: eventAId, color: Color(hex: "#5BC8FF"))
            Text("VS")
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundStyle(AppColors.textTertiary)
            slot(label: "B", eventId: eventBId, color: Color(hex: "#BF5AF2"))
        }
    }

    private func slot(label: String, eventId: String?, color: Color) -> some View {
        let event = eventId.flatMap { id in pastEvents.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 3) {
            Text("NIGHT \(label)")
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(color)
            if let e = event {
                Text(e.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                Text(e.startTime, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                Text("Not selected")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(color.opacity(eventId != nil ? 0.1 : 0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(eventId != nil ? 0.4 : 0.15), lineWidth: 1)
        )
        .cornerRadius(10)
        .animation(.easeInOut(duration: 0.2), value: eventId)
    }

    // MARK: Event Row

    private func eventRow(_ event: NightEvent) -> some View {
        let isA = eventAId == event.id
        let isB = eventBId == event.id
        let aColor = Color(hex: "#5BC8FF")
        let bColor = Color(hex: "#BF5AF2")
        let rowColor = isA ? aColor : isB ? bColor : Color.clear

        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(event.startTime, format: .dateTime.day())
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(isA ? aColor : isB ? bColor : AppColors.text)
                Text(event.startTime, format: .dateTime.month(.abbreviated))
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(.uppercase)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                Text(event.startTime, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            HStack(spacing: 6) {
                if isA { selectionBadge("A", color: aColor) }
                if isB { selectionBadge("B", color: bColor) }
                if !isA && !isB {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isA || isB ? rowColor.opacity(0.08) : AppColors.surfaceTop)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isA || isB ? rowColor.opacity(0.35) : AppColors.border, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isA || isB)
        .onTapGesture { handleTap(event.id) }
    }

    private func selectionBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .black))
            .tracking(1)
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(color.opacity(0.15))
            .clipShape(Circle())
    }

    private func handleTap(_ id: String) {
        if eventAId == id {
            eventAId = nil
        } else if eventBId == id {
            eventBId = nil
        } else if eventAId == nil {
            eventAId = id
        } else if eventBId == nil {
            eventBId = id
        } else {
            eventAId = id
        }
    }

    // MARK: Generate Button

    private var generateButton: some View {
        Button {
            guard
                let aId = eventAId, let bId = eventBId,
                let a = pastEvents.first(where: { $0.id == aId }),
                let b = pastEvents.first(where: { $0.id == bId })
            else { return }
            appState.generateComparisonReport(eventA: a, eventB: b)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .semibold))
                Text("GENERATE COMPARISON")
                    .font(.system(size: 13, weight: .black))
                    .tracking(1.5)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [AppColors.accentWarm, AppColors.accent],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .cornerRadius(30)
            .shadow(color: AppColors.accent.opacity(0.5), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }
}
