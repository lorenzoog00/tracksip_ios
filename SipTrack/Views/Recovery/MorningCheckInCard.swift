import SwiftUI

/// The check-in card at the top of Home, for the night
/// `AppState.morningCheckInEventId()` names. Tapping it opens the check-in
/// (RootView presents it from `pendingCheckIn`). With AI reports off it shows
/// the old card's "Enable AI reports in Profile…" link instead.
struct MorningCheckInCard: View {
    let eventId: String
    @EnvironmentObject var appState: AppState

    private var event: NightEvent? { appState.events.first { $0.id == eventId } }

    var body: some View {
        if let event {
            if appState.userProfile.aiReportsEnabled == true {
                Button {
                    appState.openMorningCheckIn(eventId: eventId, preselected: nil)
                } label: {
                    card(event) {
                        HStack(spacing: 10) {
                            Text(Symptom.allCases.map(\.emoji).joined(separator: " "))
                                .font(.system(size: 20))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .accessibilityHidden(true)
                            Spacer(minLength: 8)
                            HStack(spacing: 5) {
                                Text("Check in")
                                    .font(.system(size: 15, weight: .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AppColors.accent, in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the morning check-in")
            } else {
                card(event) {
                    NavigationLink(value: Route.profile) {
                        Text(MorningPlanDisplay.enableAILine)
                            .font(.footnote)
                            .foregroundStyle(AppColors.accent)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func card<Footer: View>(_ event: NightEvent, @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(MorningPlanDisplay.checkInLabel(nightStart: event.startTime))
                .font(.system(size: 11, weight: .black))
                .tracking(2)
                .foregroundStyle(AppColors.accent)
            Text(MorningPlanDisplay.checkInTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.text)
                .padding(.top, 6)
            Text(appState.morningRecap(for: event))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            footer()
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .premiumCard(tint: AppColors.accent, tintOpacity: 0.08, borderTop: AppColors.accent.opacity(0.45))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
