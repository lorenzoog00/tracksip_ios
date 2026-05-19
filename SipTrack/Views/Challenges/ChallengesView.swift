import SwiftUI

struct ChallengesView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreate = false
    @State private var showPaywall = false

    private var progresses: [ChallengeProgress] {
        appState.challenges.map {
            ChallengeUtils.progress(
                challenge: $0,
                events: appState.events,
                entries: appState.entries,
                drinkTypes: appState.allDrinkTypes,
                profile: appState.userProfile
            )
        }
    }

    private var active:  [ChallengeProgress] { progresses.filter { $0.status == .active } }
    private var history: [ChallengeProgress] { progresses.filter { $0.status != .active } }

    var body: some View {
        Group {
            if !appState.isPro {
                challengesPaywall
            } else if progresses.isEmpty {
                ZStack {
                    AppColors.background.ignoresSafeArea()
                    EmptyGoalsView { showCreate = true }
                }
            } else {
                challengesList
            }
        }
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if appState.isPro {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) { CreateGoalSheet() }
        .sheet(isPresented: $showPaywall) { ProView(presentation: .modal) }
    }

    private var challengesPaywall: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(AppColors.accent.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.accent)
                }

                VStack(spacing: 8) {
                    Text("Challenges & Goals")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    Text("Set weekly drink limits, dry weeks, calorie caps, and more. Track your progress over time.")
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

    private var challengesList: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            List {
                    if !active.isEmpty {
                        Section {
                            ForEach(active, id: \.challenge.id) { prog in
                                ChallengeCard(progress: prog)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                            .onDelete { idx in
                                idx.map { active[$0].challenge.id }.forEach { appState.deleteChallenge($0) }
                            }
                        } header: {
                            Text("Active Goals")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                                .textCase(nil)
                        }
                    }

                    if !history.isEmpty {
                        Section {
                            ForEach(history, id: \.challenge.id) { prog in
                                ChallengeCard(progress: prog)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                            .onDelete { idx in
                                idx.map { history[$0].challenge.id }.forEach { appState.deleteChallenge($0) }
                            }
                        } header: {
                            Text("History")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - Empty State

private struct EmptyGoalsView: View {
    let onTap: () -> Void

    private let suggestions: [(icon: String, title: String, desc: String)] = [
        ("wineglass",         "10 drinks / week",    "A solid start for most people"),
        ("moon.fill",         "3 nights / month",    "Keep nights out intentional"),
        ("flame.fill",        "1,200 cal / week",    "Mind what you drink"),
        ("waveform.path.ecg", "Avg BAC under 0.05%", "A measured night, every night."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("Set your first goal")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    Text("Track limits that matter to you.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 10) {
                    Text("POPULAR GOALS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.horizontal)

                    ForEach(suggestions, id: \.title) { s in
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.accentDim)
                                    .frame(width: 40, height: 40)
                                Image(systemName: s.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppColors.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.text)
                                Text(s.desc)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                        .padding(.horizontal)
                    }
                }

                Button(action: onTap) {
                    Text("Create a Goal")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .foregroundStyle(.black)
                        .cornerRadius(14)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Challenge Card

private struct ChallengeCard: View {
    let progress: ChallengeProgress

    private var statusColor: Color {
        switch progress.status {
        case .active:    return AppColors.accent
        case .completed: return AppColors.success
        case .failed:    return AppColors.danger
        case .expired:   return AppColors.textTertiary
        }
    }

    private var statusLabel: String {
        switch progress.status {
        case .active:    return "\(progress.daysLeft)d left"
        case .completed: return "Completed ✓"
        case .failed:    return "Failed"
        case .expired:   return "Expired"
        }
    }

    private var icon: String {
        switch progress.challenge.type {
        case .maxDrinksPerWeek:   return "wineglass.fill"
        case .maxNightsPerMonth:  return "calendar"
        case .dryWeek:            return "drop.slash.fill"
        case .maxDrinksPerNight:  return "moon.fill"
        case .maxCaloriesPerWeek: return "flame.fill"
        case .maxMonthlyAvgBAC:   return "waveform.path.ecg"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(progress.challenge.type.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                    Text(progress.label)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.13))
                        .cornerRadius(8)

                    if progress.status == .active {
                        Text("\(Int(progress.percentage * 100))%")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Progress bar
            GeometryReader { geo in
                let fraction = min(progress.percentage, 1.0)
                let isOver   = progress.percentage > 1.0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.border.opacity(0.4))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isOver ? AppColors.danger : statusColor)
                        .frame(width: geo.size.width * fraction)
                }
                .frame(height: 4)
            }
            .frame(height: 4)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
            progress.percentage > 1.0 ? AppColors.danger.opacity(0.4) : AppColors.border,
            lineWidth: 1
        ))
    }
}

// MARK: - Create Goal Sheet

private struct CreateGoalSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: ChallengeType = .maxDrinksPerWeek
    @State private var target: Double = ChallengeType.maxDrinksPerWeek.defaultTarget

    private var isDryWeek: Bool { selectedType == .dryWeek }

    private var typeDescription: String {
        switch selectedType {
        case .maxDrinksPerWeek:   return "Stay under \(Int(target)) drinks total across the week."
        case .maxNightsPerMonth:  return "Go out \(Int(target)) times or fewer this month."
        case .dryWeek:            return "Zero alcohol for 7 days. A reset for body and mind."
        case .maxDrinksPerNight:  return "Cap any single night at \(Int(target)) drinks."
        case .maxCaloriesPerWeek: return "Keep drink calories under \(Int(target)) this week."
        case .maxMonthlyAvgBAC:   return String(format: "Your avg BAC across all events this month stays under %.3f%%.", target)
        }
    }

    private var stepAmount: Double {
        switch selectedType {
        case .maxCaloriesPerWeek: return 50
        case .maxMonthlyAvgBAC:   return 0.005
        default:                  return 1
        }
    }

    private var targetRange: ClosedRange<Double> {
        switch selectedType {
        case .maxDrinksPerWeek:   return 1...50
        case .maxNightsPerMonth:  return 1...15
        case .dryWeek:            return 0...0
        case .maxDrinksPerNight:  return 1...20
        case .maxCaloriesPerWeek: return 100...5000
        case .maxMonthlyAvgBAC:   return 0.005...0.150
        }
    }

    private var presets: [(label: String, value: Double)] {
        switch selectedType {
        case .maxDrinksPerWeek:   return [("Easy", 14),    ("Moderate", 10),    ("Strict", 6)]
        case .maxNightsPerMonth:  return [("Easy", 6),     ("Moderate", 4),     ("Strict", 2)]
        case .dryWeek:            return []
        case .maxDrinksPerNight:  return [("Easy", 6),     ("Moderate", 4),     ("Strict", 2)]
        case .maxCaloriesPerWeek: return [("Easy", 2000),  ("Moderate", 1500),  ("Strict", 800)]
        case .maxMonthlyAvgBAC:   return [("Relaxed", 0.080), ("Moderate", 0.050), ("Strict", 0.030)]
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Type picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GOAL TYPE")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.4)
                                .foregroundStyle(AppColors.textTertiary)

                            VStack(spacing: 6) {
                                ForEach(ChallengeType.allCases, id: \.self) { type in
                                    Button {
                                        selectedType = type
                                        target = type.defaultTarget
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: iconFor(type))
                                                .font(.system(size: 15))
                                                .foregroundStyle(selectedType == type ? AppColors.accent : AppColors.textSecondary)
                                                .frame(width: 22)
                                            Text(type.label)
                                                .font(.system(size: 14, weight: selectedType == type ? .semibold : .regular))
                                                .foregroundStyle(AppColors.text)
                                            Spacer()
                                            if selectedType == type {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(AppColors.accent)
                                            }
                                        }
                                        .padding(12)
                                        .background(selectedType == type ? AppColors.accentDim : AppColors.surface)
                                        .cornerRadius(10)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                            selectedType == type ? AppColors.accent.opacity(0.4) : AppColors.border,
                                            lineWidth: 1
                                        ))
                                    }
                                }
                            }
                        }

                        // Target
                        if !isDryWeek {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("TARGET")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1.4)
                                    .foregroundStyle(AppColors.textTertiary)

                                // Presets
                                if !presets.isEmpty {
                                    HStack(spacing: 8) {
                                        ForEach(presets, id: \.label) { preset in
                                            Button {
                                                target = preset.value
                                            } label: {
                                                VStack(spacing: 2) {
                                                    Text(preset.label)
                                                        .font(.system(size: 12, weight: .semibold))
                                                    Text(targetDisplayValue(preset.value))
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(target == preset.value ? AppColors.accentDim : AppColors.surface)
                                                .foregroundStyle(target == preset.value ? AppColors.accent : AppColors.textSecondary)
                                                .cornerRadius(10)
                                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                                    target == preset.value ? AppColors.accent.opacity(0.4) : AppColors.border,
                                                    lineWidth: 1
                                                ))
                                            }
                                        }
                                    }
                                }

                                // Stepper
                                HStack {
                                    Button {
                                        if target - stepAmount >= targetRange.lowerBound {
                                            target -= stepAmount
                                        }
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(AppColors.accent)
                                            .frame(width: 44, height: 44)
                                            .background(AppColors.surface)
                                            .cornerRadius(10)
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                                    }

                                    Spacer()

                                    Text(targetDisplayValue(target))
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(AppColors.text)

                                    Spacer()

                                    Button {
                                        if target + stepAmount <= targetRange.upperBound {
                                            target += stepAmount
                                        }
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(AppColors.accent)
                                            .frame(width: 44, height: 44)
                                            .background(AppColors.surface)
                                            .cornerRadius(10)
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                                    }
                                }
                                .padding()
                                .background(AppColors.surface)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                            }
                        }

                        // Description
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(AppColors.textTertiary)
                            Text(typeDescription)
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(AppColors.surface)
                        .cornerRadius(10)

                        // Create button
                        Button {
                            let finalTarget = isDryWeek ? 0 : target
                            let now = Date()
                            let challenge = Challenge(
                                id: generateId(),
                                type: selectedType,
                                target: finalTarget,
                                startDate: now,
                                endDate: ChallengeUtils.defaultEndDate(for: selectedType, from: now),
                                createdAt: now,
                                completed: false
                            )
                            appState.addChallenge(challenge)
                            dismiss()
                        } label: {
                            Text("Start Goal")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppColors.accent)
                                .foregroundStyle(.black)
                                .cornerRadius(14)
                        }
                        .padding(.bottom, 8)
                    }
                    .padding()
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private func targetDisplayValue(_ val: Double) -> String {
        switch selectedType {
        case .maxCaloriesPerWeek: return "\(Int(val)) cal"
        case .maxMonthlyAvgBAC:   return String(format: "%.3f%%", val)
        default:                  return "\(Int(val))"
        }
    }

    private func iconFor(_ type: ChallengeType) -> String {
        switch type {
        case .maxDrinksPerWeek:   return "wineglass.fill"
        case .maxNightsPerMonth:  return "calendar"
        case .dryWeek:            return "drop.slash.fill"
        case .maxDrinksPerNight:  return "moon.fill"
        case .maxCaloriesPerWeek: return "flame.fill"
        case .maxMonthlyAvgBAC:   return "waveform.path.ecg"
        }
    }
}
