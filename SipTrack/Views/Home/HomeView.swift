import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var supabase: SupabaseManager
    @State private var showCreateEvent = false
    @State private var deletingEventId: String? = nil

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Good night"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(AppColors.text)
                            Text("Track your night")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        NavigationLink(value: Route.profile) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    if supabase.isSignedIn {
                        signedInContent
                    } else {
                        noAccountContent
                    }

                    Color.clear.frame(height: 90)
                }
                .padding(.top, 16)
            }
            .background(AppColors.background)

            if supabase.isSignedIn {
                fab
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

    // MARK: - FAB

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
        .background(AppColors.accent)
        .cornerRadius(30)
        .shadow(color: AppColors.accentGlow, radius: 12, y: 4)
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

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NavTile(title: "Calendar",   icon: "calendar",       locked: !appState.isPro, destination: .calendar)
            NavTile(title: "Stats",      icon: "chart.bar.fill", locked: !appState.isPro, destination: .dashboard)
            NavTile(title: "Challenges", icon: "trophy.fill",    locked: !appState.isPro, destination: .challenges)
            NavTile(title: "Drinks",     icon: "wineglass.fill", locked: !appState.isPro, destination: .drinks)
        }
        .padding(.horizontal)

        if !appState.visibleEvents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Past Nights")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .padding(.horizontal)

                ForEach(Array(appState.visibleEvents.enumerated()), id: \.element.id) { index, event in
                    if index == 2 && !appState.isPro {
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
                        .background(AppColors.accent)
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)

                NavigationLink(value: Route.auth) {
                    Text("Sign In")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.surface)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accent.opacity(0.4), lineWidth: 1))
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
        VStack(spacing: 0) {
            // Top row: name + elapsed
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(stage.color)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulse ? 1.5 : 1.0)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    Text(event.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                }
                Spacer()
                Text(elapsed)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.leading, 4)
            }

            Divider()
                .background(AppColors.border)
                .padding(.vertical, 12)

            // Bottom row: BAC + stage + drinks
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.3f%%", bac))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(stage.color)
                    Text(stage.name)
                        .font(.system(size: 12))
                        .foregroundStyle(stage.color.opacity(0.7))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(drinkCount)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    Text("drink\(drinkCount == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(stage.color.opacity(0.35), lineWidth: 1)
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

// MARK: - Nav tile

private struct NavTile: View {
    @EnvironmentObject var appState: AppState
    let title: String
    let icon: String
    let locked: Bool
    let destination: Route
    @State private var showPaywall = false

    var body: some View {
        Group {
            if locked {
                Button { showPaywall = true } label: { tileContent }
            } else {
                NavigationLink(value: destination) { tileContent }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private var tileContent: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(locked ? AppColors.textTertiary : AppColors.accent)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                        .offset(x: 6, y: -6)
                }
            }
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(locked ? AppColors.textTertiary : AppColors.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
    }
}

// MARK: - Event row

private struct EventRow: View {
    let event: NightEvent
    let drinkCount: Int

    private var dateString: String {
        let cal = Calendar.current
        if cal.isDateInToday(event.startTime) { return "Today" }
        if cal.isDateInYesterday(event.startTime) { return "Yesterday" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: event.startTime)
    }

    private var timeString: String {
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        return tf.string(from: event.startTime)
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                HStack(spacing: 4) {
                    Text(dateString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(timeString)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(drinkCount)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                Text("drink\(drinkCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(14)
        .background(AppColors.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }
}
