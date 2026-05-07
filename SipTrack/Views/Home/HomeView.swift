import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var firebase: FirebaseManager
    @State private var showCreateEvent = false
    @State private var deletingEventId: String? = nil

    private var dayString: String {
        let df = DateFormatter(); df.dateFormat = "EEEE"
        return df.string(from: Date()).uppercased()
    }
    private var dateNumberString: String {
        let df = DateFormatter(); df.dateFormat = "d"
        return df.string(from: Date())
    }
    private var monthYearString: String {
        let df = DateFormatter(); df.dateFormat = "MMMM yyyy"
        return df.string(from: Date())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background with top ambient glow
            AppColors.background.ignoresSafeArea()
            LinearGradient(
                colors: [AppColors.accent.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.28)
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    if firebase.isSignedIn {
                        signedInContent
                    } else {
                        noAccountContent
                    }
                    Color.clear.frame(height: 90)
                }
                .padding(.top, 16)
            }

            if firebase.isSignedIn {
                fab
            }

            if appState.syncFailed {
                syncErrorBanner
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showCreateEvent) {
            CreateEventView()
        }
        .confirmationDialog("Delete this night?", isPresented: Binding(
            get: { deletingEventId != nil },
            set: { if !$0 { deletingEventId = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = deletingEventId {
                    appState.deleteEvent(id)
                    deletingEventId = nil
                }
            }
            Button("Cancel", role: .cancel) { deletingEventId = nil }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(dayString)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(AppColors.textTertiary)
                Text(dateNumberString)
                    .font(.system(size: 54, weight: .bold, design: .serif))
                    .foregroundStyle(AppColors.text)
                    .padding(.top, -2)
                Text(monthYearString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, -6)
            }
            Spacer()
            NavigationLink(value: Route.profile) {
                ZStack {
                    Circle()
                        .fill(AppColors.surfaceTop)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(AppColors.border, lineWidth: 1))
                    Image(systemName: "person.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }

    // MARK: - FAB

    @ViewBuilder
    private var syncErrorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(AppColors.danger)
            Text("Sync failed")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.text)
            Spacer()
            Button {
                appState.retrySync()
            } label: {
                Text("Retry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(AppColors.danger.opacity(0.4))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var fab: some View {
        if let active = appState.activeEvent {
            NavigationLink(value: Route.event(active.id)) {
                fabLabel(title: "View Active Night", icon: "arrow.up.right")
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        } else {
            Button { showCreateEvent = true } label: {
                fabLabel(title: "Start New Night", icon: "plus")
            }
            .padding(.bottom, 32)
        }
    }

    private func fabLabel(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [AppColors.accentWarm, AppColors.accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(30)
        .shadow(color: AppColors.accent.opacity(0.55), radius: 16, y: 6)
        .shadow(color: AppColors.accent.opacity(0.18), radius: 36, y: 10)
    }

    // MARK: - Signed-in content

    @ViewBuilder
    private var signedInContent: some View {
        if let active = appState.activeEvent {
            NavigationLink(value: Route.event(active.id)) {
                ActiveEventCard(event: active)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }

        // Feature cards section
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("EXPLORE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppColors.textTertiary)
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    FeatureCard(
                        title: "Calendar",
                        icon: "calendar",
                        accent: Color(hex: "#6B99FF"),
                        locked: !appState.isPro,
                        destination: .calendar
                    ) { CalendarDotsPreview() }

                    FeatureCard(
                        title: "Stats",
                        icon: "chart.bar.fill",
                        accent: AppColors.accent,
                        locked: !appState.isPro,
                        destination: .dashboard
                    ) { StatsCardPreview() }

                    FeatureCard(
                        title: "Challenges",
                        icon: "trophy.fill",
                        accent: Color(hex: "#E8834A"),
                        locked: !appState.isPro,
                        destination: .challenges
                    ) { ChallengesCardPreview() }

                    FeatureCard(
                        title: "Drinks",
                        icon: "wineglass.fill",
                        accent: Color(hex: "#3DBDA7"),
                        locked: !appState.isPro,
                        destination: .drinks
                    ) { DrinksCardPreview() }
                }
                .padding(.horizontal)
            }
        }

        // Past nights section
        if !appState.visibleEvents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("PAST NIGHTS")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(AppColors.textTertiary)
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(height: 0.5)
                }
                .padding(.horizontal)

                ForEach(Array(appState.visibleEvents.enumerated()), id: \.element.id) { index, event in
                    if index % 2 == 1 && !appState.isPro {
                        NativeAdCardView()
                            .padding(.horizontal)
                    }
                    NavigationLink(value: Route.summary(event.id)) {
                        EventRow(event: event, drinkCount: appState.totalDrinks(for: event.id))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .contextMenu {
                        Button(role: .destructive) {
                            deletingEventId = event.id
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } else if appState.activeEvent == nil {
            EmptyNightsState()
        }
    }

    // MARK: - Signed-out content

    @ViewBuilder
    private var noAccountContent: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 24)

            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.accent)

            VStack(spacing: 8) {
                Text("Create an account to get started")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.text)
                    .multilineTextAlignment(.center)
                Text("Your nights are saved to your account and stay private to you.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                NavigationLink(value: Route.auth) {
                    Text("Create Account")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [AppColors.accentWarm, AppColors.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: AppColors.accent.opacity(0.4), radius: 12, y: 4)
                }
                .buttonStyle(.plain)

                NavigationLink(value: Route.auth) {
                    Text("Sign In")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .premiumCard(
                            radius: 14,
                            borderTop: AppColors.accent.opacity(0.4),
                            borderBottom: AppColors.border
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Active event card

private struct ActiveEventCard: View {
    @EnvironmentObject var appState: AppState
    let event: NightEvent

    private var bac: Double { appState.currentBAC(for: event.id) }
    private var stage: IntoxicationStage { IntoxicationStage.stage(for: bac) }
    private var drinkCount: Int { appState.totalDrinks(for: event.id) }
    private var elapsed: String {
        let mins = Int(max(0, -event.startTime.timeIntervalSinceNow) / 60)
        let h = mins / 60; let m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stage badge + elapsed
            HStack {
                Text(stage.name.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2.2)
                    .foregroundStyle(stage.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(stage.color.opacity(0.14))
                    .cornerRadius(4)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(stage.color)
                        .frame(width: 5, height: 5)
                        .scaleEffect(pulse ? 1.6 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                    Text(elapsed)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            // BAC — serif, large, no glow orb
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(String(format: "%.3f", bac))
                    .font(.system(size: 58, weight: .bold, design: .serif))
                    .foregroundStyle(stage.color)
                Text("%")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(stage.color.opacity(0.55))
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            // Footer: event name + drink count
            HStack {
                Text(event.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(drinkCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    Text(drinkCount == 1 ? "drink" : "drinks")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .premiumCard(
            radius: 20,
            tint: stage.color,
            tintOpacity: 0.05,
            borderTop: stage.color.opacity(0.35),
            borderBottom: stage.color.opacity(0.05)
        )
        .onAppear { pulse = true }
    }
}

// MARK: - Empty state

private struct EmptyNightsState: View {
    @State private var glow = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 8)

            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(glow ? 0.18 : 0.10))
                    .frame(width: 100, height: 100)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: glow)
                Circle()
                    .fill(AppColors.accentDim)
                    .frame(width: 76, height: 76)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(AppColors.accent)
            }
            .onAppear { glow = true }

            VStack(spacing: 8) {
                Text("No nights tracked yet")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.text)
                Text("Tap \"Start New Night\" to begin\ntracking your first evening.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer().frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

// MARK: - Feature card

private struct FeatureCard<Content: View>: View {
    let title: String
    let icon: String
    let accent: Color
    let locked: Bool
    let destination: Route
    @ViewBuilder let previewContent: () -> Content
    @State private var showPaywall = false

    var body: some View {
        Group {
            if locked {
                Button { showPaywall = true } label: { card }
            } else {
                NavigationLink(value: destination) { card }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(locked ? AppColors.textTertiary : accent)
                Spacer()
                if locked {
                    Text("PRO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppColors.accentDim)
                        .cornerRadius(6)
                }
            }

            Spacer(minLength: 10)

            previewContent()
                .opacity(locked ? 0.45 : 1.0)

            Spacer(minLength: 10)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(locked ? AppColors.textTertiary : AppColors.textSecondary)
        }
        .padding(14)
        .frame(width: 152, height: 144)
        .premiumCard(
            radius: 18,
            tint: locked ? .clear : accent,
            tintOpacity: locked ? 0 : 0.06,
            borderTop: locked ? AppColors.rimLight : accent.opacity(0.45),
            borderBottom: AppColors.border
        )
    }
}

// MARK: - Feature card previews

private struct CalendarDotsPreview: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: -(6 - offset), to: Date())!
                    let hasEvent = appState.visibleEvents.contains {
                        Calendar.current.isDate($0.startTime, inSameDayAs: date)
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(hasEvent ? Color(hex: "#6B99FF") : AppColors.border)
                        .frame(width: 13, height: 26)
                }
            }
            Text("last 7 days")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
        }
    }
}

private struct StatsCardPreview: View {
    @EnvironmentObject var appState: AppState

    private var lastNightDrinks: Int? {
        guard let last = appState.visibleEvents.first else { return nil }
        return appState.totalDrinks(for: last.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lastNightDrinks.map { "\($0)" } ?? "—")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.text)
            Text(lastNightDrinks != nil ? "last night" : "no data yet")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
        }
    }
}

private struct ChallengesCardPreview: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(appState.challenges.count)")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.text)
            Text("active")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
        }
    }
}

private struct DrinksCardPreview: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(appState.allDrinkTypes.count)")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.text)
            Text("drink types")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
        }
    }
}

// MARK: - Event row

private struct EventRow: View {
    let event: NightEvent
    let drinkCount: Int

    private var dayNumber: String {
        DateFormatter().then { $0.dateFormat = "d" }.string(from: event.startTime)
    }

    private var monthAbbr: String {
        DateFormatter().then { $0.dateFormat = "MMM" }.string(from: event.startTime).uppercased()
    }

    private var timeString: String {
        DateFormatter().then { $0.dateFormat = "h:mm a" }.string(from: event.startTime)
    }

    private var isToday: Bool    { Calendar.current.isDateInToday(event.startTime) }
    private var isYesterday: Bool { Calendar.current.isDateInYesterday(event.startTime) }

    var body: some View {
        HStack(spacing: 14) {
            // Date column — serif, no separator line
            VStack(spacing: 0) {
                if isToday {
                    Text("NOW")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.accent)
                    Text(dayNumber)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(AppColors.accent)
                } else if isYesterday {
                    Text("YEST")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(dayNumber)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(AppColors.text)
                } else {
                    Text(dayNumber)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(AppColors.text)
                    Text(monthAbbr)
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .frame(width: 38)

            // Event info
            VStack(alignment: .leading, spacing: 3) {
                Text(event.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                Text(timeString)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            // Drink count pill + chevron
            HStack(spacing: 8) {
                Text("\(drinkCount)")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AppColors.accentDim)
                    .cornerRadius(20)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .premiumCard(radius: 16)
    }
}

// MARK: - DateFormatter convenience

private extension DateFormatter {
    func then(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        configure(self)
        return self
    }
}
