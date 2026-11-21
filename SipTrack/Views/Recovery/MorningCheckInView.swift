import SwiftUI

/// The sheet RootView presents for `AppState.pendingCheckIn`. A night that
/// already had its plan when the sheet opened (an old notification) opens
/// straight on the plan; otherwise on the check-in, which pushes the plan when
/// it arrives. Closing sets `pendingCheckIn` back to nil.
struct MorningCheckInSheet: View {
    let pending: PendingCheckIn
    @EnvironmentObject var appState: AppState
    /// Decided once, when the sheet opens: a plan that arrives while the
    /// check-in is on screen is pushed, not swapped in.
    @State private var opensOnPlan: Bool

    init(pending: PendingCheckIn, opensOnPlan: Bool) {
        self.pending = pending
        _opensOnPlan = State(initialValue: opensOnPlan)
    }

    var body: some View {
        NavigationStack {
            if opensOnPlan {
                RecoveryPlanView(eventId: pending.eventId, onDone: { appState.pendingCheckIn = nil })
            } else {
                MorningCheckInView(eventId: pending.eventId, preselected: pending.preselected)
            }
        }
    }
}

/// "How are you feeling?": six tiles (more than one can be picked), then
/// "Get my plan". Building shows the EKG loading line; a ready plan (or the
/// locked sample for a free user out of plans) is pushed.
struct MorningCheckInView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @State private var selected: Set<Symptom>

    init(eventId: String, preselected: Symptom?) {
        self.eventId = eventId
        var initial: Set<Symptom> = []
        if let preselected { initial.insert(preselected) }
        _selected = State(initialValue: initial)
    }

    private var event: NightEvent? { appState.events.first { $0.id == eventId } }
    private var isBuilding: Bool { appState.buildingMorningPlanFor == eventId }
    private var isFailed: Bool { appState.morningPlanFailed.contains(eventId) }
    private var isUnavailable: Bool { appState.morningPlanUnavailable.contains(eventId) }
    private var aiEnabled: Bool { appState.userProfile.aiReportsEnabled == true }
    /// The plan, or the locked sample, is what comes next.
    private var hasResult: Bool {
        appState.morningPlans[eventId] != nil || appState.morningPlanLocked.contains(eventId)
    }

    private func close() {
        appState.pendingCheckIn = nil
    }

    var body: some View {
        ScrollView {
            if let event {
                content(event)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
            } else {
                Text("This night is no longer here.")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityLabel("Close")
            }
        }
        // Pushed when the plan (or the locked sample) arrives. The plan view
        // hides its back button, so this only goes back when the lock lifts
        // after a Pro purchase, to the answers already picked.
        .navigationDestination(isPresented: Binding(get: { hasResult }, set: { _ in })) {
            RecoveryPlanView(eventId: eventId, onDone: { close() })
        }
    }

    private func content(_ event: NightEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(MorningPlanDisplay.checkInLabel(nightStart: event.startTime))
                .font(.system(size: 11, weight: .black))
                .tracking(2)
                .foregroundStyle(AppColors.accent)

            Text(MorningPlanDisplay.checkInTitle)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(AppColors.text)
                .padding(.top, 8)

            Text(appState.morningRecap(for: event))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(Symptom.allCases, id: \.self) { symptom in
                    tile(symptom)
                }
            }
            .disabled(isBuilding || isUnavailable)
            .padding(.top, 24)

            Text(MorningPlanDisplay.checkInHint)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            Text(MorningPlanDisplay.disclosure)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            action
                .padding(.top, 18)
        }
    }

    // MARK: - Tiles

    private func tile(_ symptom: Symptom) -> some View {
        let on = selected.contains(symptom)
        return Button {
            selected = MorningCheckIn.toggle(symptom, in: selected)
            Haptics.shared.play(.selection)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(symptom.emoji)
                    .font(.system(size: 28))
                Text(symptom.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .background(on ? AppColors.accent.opacity(0.13) : AppColors.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(on ? AppColors.accent : AppColors.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symptom.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Button and states

    @ViewBuilder
    private var action: some View {
        if isBuilding {
            buildingState
        } else if !aiEnabled {
            aiOffState
        } else if isUnavailable {
            unavailableState
        } else if isFailed {
            failedState
        } else {
            getPlanButton
        }
    }

    private var getPlanButton: some View {
        Button {
            appState.requestMorningPlan(eventId: eventId, symptoms: selected)
        } label: {
            Text(MorningPlanDisplay.checkInButton)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty || appState.buildingMorningPlanFor != nil)
        .opacity(selected.isEmpty ? 0.45 : 1)
    }

    /// The EKG line the night analysis used while it was being written.
    private var buildingState: some View {
        VStack(spacing: 14) {
            AnalysisEKGLine(accentColor: AppColors.accent)
                .frame(height: 48)
                .padding(.horizontal, 4)
            VStack(spacing: 4) {
                Text("BUILDING YOUR PLAN")
                    .font(.system(size: 12, weight: .black))
                    .tracking(2.5)
                    .foregroundStyle(AppColors.accent)
                Text("Picking what fits this morning…")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .premiumCard(radius: 16)
    }

    private var failedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.orange)
            VStack(spacing: 4) {
                Text("PLAN FAILED")
                    .font(.system(size: 12, weight: .black))
                    .tracking(2.5)
                    .foregroundStyle(Color.orange)
                Text("Could not reach AI service")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
            }
            Button {
                appState.requestMorningPlan(eventId: eventId, symptoms: selected)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("RETRY")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1.5)
                }
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(AppColors.accentDim)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty || appState.buildingMorningPlanFor != nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .premiumCard(radius: 16)
    }

    /// The server had nothing in its library for this check-in. Not an error
    /// and not the paywall: a plain note, and a way to answer again.
    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            Text(MorningPlanDisplay.unavailableLine)
                .font(.system(size: 16))
                .foregroundStyle(AppColors.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 20) {
                Button("Change my answers") { _ = appState.morningPlanUnavailable.remove(eventId) }
                Button("Close") { close() }
                    .fontWeight(.semibold)
            }
            .font(.system(size: 15))
            .tint(AppColors.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .premiumCard(radius: 16)
    }

    /// AI reports were turned off after the notification was scheduled. Same
    /// wording as the old card; Profile is pushed on Home, under this sheet.
    private var aiOffState: some View {
        Button {
            close()
            appState.pendingEventRoute = .profile
        } label: {
            Text(MorningPlanDisplay.enableAILine)
                .font(.footnote)
                .foregroundStyle(AppColors.accent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
                .premiumCard(radius: 16)
        }
        .buttonStyle(.plain)
    }
}
