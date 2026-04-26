import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreateEvent  = false
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

                    // Active event card
                    if let active = appState.activeEvent {
                        NavigationLink(value: Route.event(active.id)) {
                            ActiveEventCard(event: active)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }

                    // Nav grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        NavTile(title: "Calendar", icon: "calendar", locked: !appState.isPro, destination: .calendar)
                        NavTile(title: "Stats",    icon: "chart.bar.fill", locked: !appState.isPro, destination: .dashboard)
                        NavTile(title: "Challenges",icon: "trophy.fill",  locked: !appState.isPro, destination: .challenges)
                        NavTile(title: "Drinks",   icon: "wineglass.fill", locked: !appState.isPro, destination: .drinks)
                    }
                    .padding(.horizontal)

                    // Past events
                    if !appState.visibleEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Past Nights")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.text)
                                .padding(.horizontal)

                            ForEach(Array(appState.visibleEvents.enumerated()), id: \.element.id) { index, event in
                                // Inject native ad after position 2 (3rd item) for free users
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
                                        appState.deleteEvent(event.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    Color.clear.frame(height: 90)
                }
                .padding(.top, 16)
            }
            .background(AppColors.background)

            // FAB
            Button {
                if appState.activeEvent != nil {
                    // Already active, do nothing (card shows it)
                } else {
                    showCreateEvent = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text(appState.activeEvent == nil ? "Start New Night" : "Night in Progress")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(AppColors.accent)
                .cornerRadius(30)
                .shadow(color: AppColors.accentGlow, radius: 12, y: 4)
            }
            .padding(.bottom, 32)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showCreateEvent) {
            CreateEventView()
        }
    }
}

// MARK: - Sub-components

private struct ActiveEventCard: View {
    @EnvironmentObject var appState: AppState
    let event: NightEvent

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.accentDim)
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 12, height: 12)
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(), value: true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(event.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Text("Active • Tap to open")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(16)
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.accent.opacity(0.4), lineWidth: 1)
        )
    }
}

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

private struct EventRow: View {
    let event: NightEvent
    let drinkCount: Int

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Text(Self.dateFormatter.string(from: event.startTime))
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
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
