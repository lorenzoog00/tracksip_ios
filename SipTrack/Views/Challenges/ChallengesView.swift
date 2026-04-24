import SwiftUI

struct ChallengesView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreate = false

    private var progresses: [ChallengeProgress] {
        appState.challenges.map {
            ChallengeUtils.progress(
                challenge: $0,
                events: appState.events,
                entries: appState.entries,
                drinkTypes: appState.allDrinkTypes
            )
        }
    }

    private var active:  [ChallengeProgress] { progresses.filter { $0.status == .active } }
    private var history: [ChallengeProgress] { progresses.filter { $0.status != .active } }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            Group {
                if progresses.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.textTertiary)
                        Text("No challenges yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                        Text("Set a personal goal to track your progress.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        if !active.isEmpty {
                            Section("Active") {
                                ForEach(active, id: \.challenge.id) { prog in
                                    ChallengeCard(progress: prog)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                }
                                .onDelete { idx in
                                    let ids = idx.map { active[$0].challenge.id }
                                    ids.forEach { appState.deleteChallenge($0) }
                                }
                            }
                        }
                        if !history.isEmpty {
                            Section("History") {
                                ForEach(history, id: \.challenge.id) { prog in
                                    ChallengeCard(progress: prog)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                }
                                .onDelete { idx in
                                    let ids = idx.map { history[$0].challenge.id }
                                    ids.forEach { appState.deleteChallenge($0) }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColors.accent)
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateChallengeSheet()
        }
    }
}

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

    var body: some View {
        HStack(spacing: 14) {
            // Ring
            ZStack {
                Circle()
                    .stroke(AppColors.border, lineWidth: 4)
                    .frame(width: 52, height: 52)
                Circle()
                    .trim(from: 0, to: min(progress.percentage, 1.0))
                    .stroke(statusColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(-90))
                Text(progress.percentage >= 1.0 ? "✓" : "\(Int(progress.percentage * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(progress.challenge.type.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Text(progress.label)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Text(statusLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .cornerRadius(8)
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
    }
}

private struct CreateChallengeSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: ChallengeType = .maxDrinksPerWeek
    @State private var targetString = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Challenge Type")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        ForEach(ChallengeType.allCases, id: \.self) { type in
                            Button { selectedType = type } label: {
                                HStack {
                                    Text(type.label)
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppColors.text)
                                    Spacer()
                                    if selectedType == type {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(AppColors.accent)
                                    }
                                }
                                .padding(12)
                                .background(selectedType == type ? AppColors.accentDim : AppColors.surface)
                                .cornerRadius(10)
                            }
                        }
                    }

                    if selectedType != .dryWeek {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Target")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                            TextField("e.g. \(Int(selectedType.defaultTarget))", text: $targetString)
                                .keyboardType(.numberPad)
                                .padding(12)
                                .background(AppColors.surface)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                                .foregroundStyle(AppColors.text)
                        }
                    }

                    Spacer()

                    Button {
                        let target = Double(targetString) ?? selectedType.defaultTarget
                        let now    = Date()
                        let challenge = Challenge(
                            id: generateId(),
                            type: selectedType,
                            target: target,
                            startDate: now,
                            endDate: ChallengeUtils.defaultEndDate(for: selectedType, from: now),
                            createdAt: now,
                            completed: false
                        )
                        appState.addChallenge(challenge)
                        dismiss()
                    } label: {
                        Text("Create Challenge")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppColors.accent)
                            .foregroundStyle(.black)
                            .cornerRadius(14)
                    }
                }
                .padding()
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
}
