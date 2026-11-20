import SwiftUI

/// A night's morning recovery plan: layout A, one scrolling checklist. For a
/// free user out of plans (`morningPlanLocked`) it shows `MorningPlan.sample`
/// blurred behind an upgrade button instead, and makes no request.
struct RecoveryPlanView: View {
    let eventId: String
    /// Set when the plan is shown in the check-in sheet: a Done button that
    /// closes the sheet replaces the back button.
    var onDone: (() -> Void)? = nil

    @EnvironmentObject var appState: AppState
    @State private var showPaywall = false

    private var record: MorningRecord? { appState.morningPlans[eventId] }
    private var isLocked: Bool { record == nil && appState.morningPlanLocked.contains(eventId) }

    var body: some View {
        ScrollView {
            if let record {
                RecoveryPlanContent(eventId: eventId, plan: record.plan, symptoms: record.symptoms,
                                    severity: record.severity, safety: record.safety)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            } else if isLocked {
                lockedContent
            } else {
                Text("No plan for this night yet.")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(onDone != nil)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if let onDone {
                    Button("Done") { onDone() }
                        .fontWeight(.semibold)
                        .tint(AppColors.accent)
                }
            }
        }
        // A Pro purchase unlocks this night: back to the check-in, whose
        // answers are still picked, to ask for the real plan.
        .sheet(isPresented: $showPaywall, onDismiss: {
            if appState.isPro { _ = appState.morningPlanLocked.remove(eventId) }
        }) {
            ProView(presentation: .modal)
        }
        .task(id: eventId) { await pollForPhotos() }
    }

    /// A photo still being generated when the plan arrived lands in the plan
    /// doc later: re-read it every 5 s for up to 60 s while this is on screen.
    /// The icon tile shows meanwhile, and stays if the photo never comes.
    private func pollForPhotos() async {
        for _ in 0..<MorningPlanDisplay.photoPollAttempts {
            guard let plan = appState.morningPlans[eventId]?.plan,
                  MorningPlanDisplay.hasMissingPhotos(plan) else { return }
            try? await Task.sleep(for: .seconds(MorningPlanDisplay.photoPollSeconds))
            if Task.isCancelled { return }
            await appState.refreshMorningPlan(eventId: eventId)
        }
    }

    // MARK: - Locked

    private var lockedContent: some View {
        RecoveryPlanContent(eventId: "sample", plan: .sample, symptoms: [.headache, .wrecked],
                            severity: "moderate", safety: PlanSafety(dontDrive: false, medicalHelp: false))
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .blur(radius: 9)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay(alignment: .top) { proGate.padding(.top, 90) }
            .clipped()
    }

    private var proGate: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            }
            VStack(spacing: 6) {
                Text("You've used your free plans")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AppColors.text)
                Text("Free accounts get \(MorningCheckIn.freeMonthlyPlans) recovery plans a month. Pro gets one every morning.")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { showPaywall = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 15))
                    Text("Unlock with Pro")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [AppColors.accentWarm, AppColors.accent],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(24)
                .shadow(color: AppColors.accent.opacity(0.5), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AppColors.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppColors.border, lineWidth: 1))
        .padding(.horizontal, 24)
    }
}

// MARK: - The checklist

/// The plan itself, top to bottom: label, symptom pills, headline, Right now,
/// Breakfast, Today, Skip, then the safety lines.
struct RecoveryPlanContent: View {
    let eventId: String
    let plan: MorningPlan
    let symptoms: [Symptom]
    let severity: String
    let safety: PlanSafety

    private var recoveryMode: Bool { MorningPlanDisplay.isRecoveryMode(severity: severity) }
    private var tone: Color { recoveryMode ? AppColors.danger : AppColors.accent }
    private var firstFood: Bool { MorningPlanDisplay.isFirstFood(severity: severity, symptoms: symptoms) }

    private func tickKey(_ item: String) -> String {
        MorningPlanDisplay.tickKey(eventId: eventId, item: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(MorningPlanDisplay.label(severity: severity))
                .font(.system(size: 11, weight: .black))
                .tracking(2)
                .foregroundStyle(tone)

            if !symptoms.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(symptoms, id: \.self) { symptom in
                            Text("\(symptom.emoji) \(symptom.label)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(tone)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(tone.opacity(0.14), in: Capsule())
                        }
                    }
                }
                .padding(.top, 10)
            }

            Text(plan.headline)
                .font(.system(size: 22, design: .serif))
                .foregroundStyle(AppColors.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            if !plan.rightNow.isEmpty {
                sectionTitle("RIGHT NOW")
                VStack(spacing: 8) {
                    ForEach(Array(plan.rightNow.enumerated()), id: \.offset) { _, remedy in
                        PlanRemedyRow(remedy: remedy, tone: tone, tickKey: tickKey(remedy.title))
                    }
                }
            }

            sectionTitle(MorningPlanDisplay.breakfastTitle(when: plan.breakfast.when, firstFood: firstFood))
            PlanPhotoCard(item: plan.breakfast, icon: "fork.knife", colors: PlanPhoto.food,
                          photoHeight: 160, tickKey: tickKey(plan.breakfast.itemId))
            if let fallback = plan.fallback {
                Text(MorningPlanDisplay.fallbackLine(title: fallback.title, firstFood: firstFood))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
                    .padding(.top, 8)
            }

            if !plan.activities.isEmpty {
                sectionTitle("TODAY")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
                                   count: min(2, plan.activities.count)),
                    alignment: .leading, spacing: 10
                ) {
                    ForEach(Array(plan.activities.enumerated()), id: \.offset) { _, activity in
                        PlanPhotoCard(item: activity, icon: "sun.max.fill", colors: PlanPhoto.outdoors,
                                      photoHeight: plan.activities.count > 1 ? 100 : 140,
                                      tickKey: tickKey(activity.itemId))
                    }
                }
            }

            if let skip = plan.skip {
                sectionTitle("SKIP")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(AppColors.danger)
                    Text(MorningPlanDisplay.skipLine(title: skip.title, why: skip.why))
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 2)
            }

            let lines = MorningPlanDisplay.safetyLines(safety)
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines, id: \.self) { line in
                        PlanSafetyLine(text: line)
                    }
                }
                .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .black))
            .tracking(1.8)
            .foregroundStyle(AppColors.textTertiary)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }
}

// MARK: - Rows

/// The round tick every item carries. Stored per item on the phone only.
private struct PlanTick: View {
    let isOn: Bool
    let tone: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(isOn ? tone : AppColors.border, lineWidth: 2)
                .frame(width: 22, height: 22)
            if isOn {
                Circle()
                    .fill(tone)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.black)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A "Right now" remedy: tick, SF Symbol, title and reason.
private struct PlanRemedyRow: View {
    let remedy: PlanRemedy
    let tone: Color
    @AppStorage private var ticked: Bool

    init(remedy: PlanRemedy, tone: Color, tickKey: String) {
        self.remedy = remedy
        self.tone = tone
        _ticked = AppStorage(wrappedValue: false, tickKey)
    }

    var body: some View {
        Button {
            ticked.toggle()
            Haptics.shared.play(.selection)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                PlanTick(isOn: ticked, tone: tone)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: remedy.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tone)
                        Text(remedy.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ticked ? AppColors.textSecondary : AppColors.text)
                            .strikethrough(ticked, color: AppColors.textSecondary)
                    }
                    Text(remedy.why)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(ticked ? .isSelected : [])
        .accessibilityHint("Tick it off")
    }
}

/// A breakfast or an activity: the photo (or its icon tile), then a tick, the
/// name and the reason.
private struct PlanPhotoCard: View {
    let item: PlanPhotoItem
    let icon: String
    let colors: [Color]
    let photoHeight: CGFloat
    @AppStorage private var ticked: Bool

    init(item: PlanPhotoItem, icon: String, colors: [Color], photoHeight: CGFloat, tickKey: String) {
        self.item = item
        self.icon = icon
        self.colors = colors
        self.photoHeight = photoHeight
        _ticked = AppStorage(wrappedValue: false, tickKey)
    }

    var body: some View {
        Button {
            ticked.toggle()
            Haptics.shared.play(.selection)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                PlanPhoto(url: item.photoUrl, icon: icon, colors: colors)
                    .frame(height: photoHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                HStack(alignment: .top, spacing: 10) {
                    PlanTick(isOn: ticked, tone: AppColors.accent)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ticked ? AppColors.textSecondary : AppColors.text)
                            .strikethrough(ticked, color: AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.why)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(ticked ? .isSelected : [])
        .accessibilityHint("Tick it off")
    }
}

/// The photo, over an icon tile that shows while it loads, when there is no
/// photo yet and when loading fails. Never a spinner: the tile is the
/// placeholder.
struct PlanPhoto: View {
    let url: URL?
    let icon: String
    let colors: [Color]

    static let food = [Color(hex: "#F7B733"), Color(hex: "#E8762B"), Color(hex: "#7A3B16")]
    static let outdoors = [Color(hex: "#7FD1AE"), Color(hex: "#2D8A6A"), Color(hex: "#164A3A")]

    var body: some View {
        // The tile sets the size; the photo is an overlay so its fill can
        // never widen the layout, and the caller clips it.
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        }
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

/// A safety line from `PlanSafety`, in the danger style.
private struct PlanSafetyLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.danger)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#FFB3BA"))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppColors.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.danger.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
