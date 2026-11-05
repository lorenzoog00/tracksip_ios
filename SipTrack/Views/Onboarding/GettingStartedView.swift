import SwiftUI

private enum SetupStep: Int, CaseIterable, Identifiable {
    case water = 0
    case calories = 1
    case analysis = 2
    case firstNight = 3
    case logDrink = 4

    var id: Self { self }
    var flag: Int { 1 << rawValue }

    var title: String {
        switch self {
        case .water: return "Water reminders"
        case .calories: return "Drink calories"
        case .analysis: return "AI night analysis"
        case .firstNight: return "Track your first night"
        case .logDrink: return "Log a drink"
        }
    }

    var icon: String {
        switch self {
        case .water: return "drop.fill"
        case .calories: return "flame.fill"
        case .analysis: return "sparkles"
        case .firstNight: return "moon.stars.fill"
        case .logDrink: return "wineglass.fill"
        }
    }

    static func progressKey(userID: String) -> String {
        "getting-started.v1.\(userID)"
    }

    static func remaining(in progress: Int) -> [Self] {
        allCases.filter { progress & $0.flag == 0 }
    }
}

struct GettingStartedCard: View {
    @AppStorage private var progress: Int

    init(userID: String) {
        _progress = AppStorage(wrappedValue: 0, SetupStep.progressKey(userID: userID))
    }

    var body: some View {
        let remaining = SetupStep.remaining(in: progress).count
        let total = SetupStep.allCases.count
        if remaining > 0 {
            NavigationLink(value: Route.gettingStarted) {
                HStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(AppColors.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Get started with Tracksip")
                            .font(.headline)
                            .foregroundStyle(AppColors.text)
                        Text("\(total - remaining) of \(total) steps complete")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .premiumCard(tint: AppColors.accent, tintOpacity: 0.08)
            }
            .buttonStyle(.plain)
        }
    }
}

struct GettingStartedView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var progress: Int
    @State private var expandedStep: SetupStep?
    @State private var newNightGuide: EventGuideTarget?
    @State private var showCelebration = false
    @AccessibilityFocusState private var celebrationFocused: Bool

    init(userID: String) {
        let key = SetupStep.progressKey(userID: userID)
        _progress = AppStorage(wrappedValue: 0, key)
        _expandedStep = State(initialValue: SetupStep.remaining(in: UserDefaults.standard.integer(forKey: key)).first)
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showCelebration {
                        celebration
                            .transition(reduceMotion ? .identity : .scale(scale: 0.88).combined(with: .opacity))
                    } else {
                        checklist
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: expandedStep) { _, step in
                guard let step else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    scroll.scrollTo(step, anchor: .top)
                }
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Getting Started")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $newNightGuide) { target in
            CreateEventView(guideTarget: target)
        }
    }

    private var checklist: some View {
        let total = SetupStep.allCases.count
        let done = total - SetupStep.remaining(in: progress).count
        return VStack(alignment: .leading, spacing: 14) {
            Text(done == total ? "You're set up" : "Make Tracksip yours")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Tap a link, then check off the step.")
                .foregroundStyle(AppColors.textSecondary)
            ProgressView(value: Double(done), total: Double(total)) {
                Text("\(done) of \(total) steps complete")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(AppColors.accent)
            .padding(.bottom, 6)

            ForEach(SetupStep.allCases) { step in
                let isComplete = progress & step.flag != 0
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedStep == step },
                    set: { expandedStep = $0 ? step : nil }
                )) {
                    VStack(alignment: .leading, spacing: 14) {
                        controls(for: step)
                        if !isComplete {
                            Button("Mark done") { complete(step) }
                                .buttonStyle(.bordered)
                                .tint(AppColors.accent)
                        }
                    }
                    .font(.subheadline)
                    .padding(.top, 12)
                } label: {
                    Label(step.title, systemImage: isComplete ? "checkmark.circle.fill" : step.icon)
                        .font(.headline)
                        .foregroundStyle(isComplete ? AppColors.success : AppColors.text)
                        .accessibilityValue(isComplete ? Text("Complete") : Text("Incomplete"))
                }
                .padding(16)
                .premiumCard()
                .id(step)
            }
        }
    }

    @ViewBuilder
    private func controls(for step: SetupStep) -> some View {
        switch step {
        case .water:
            Text("Set an interval, like 25 minutes. Logging water restarts the timer.")
                .foregroundStyle(AppColors.textSecondary)
            guideLink("Show me water reminders", to: .guidedProfile(.water))
        case .calories:
            Text("Enter calories per serving from the label, or set a nightly calorie warning.")
                .foregroundStyle(AppColors.textSecondary)
            guideLink("Show me calories per serving", to: .guidedDrinkCalories)
            guideLink("Show me the nightly calorie limit", to: .guidedProfile(.calories))
        case .analysis:
            Text("Turn on AI reports to review your drinking pace in the night summary.")
                .foregroundStyle(AppColors.textSecondary)
            guideLink("Show me where to enable AI reports", to: .guidedProfile(.analysis))
        case .firstNight:
            Text("Start a night to track drinks, water and food. End it to see your summary.")
                .foregroundStyle(AppColors.textSecondary)
            if let active = appState.activeEvent {
                guideLink("Show me where to log water", to: .guidedEvent(active.id, .water))
            } else {
                startNightLink(for: .water)
            }
        case .logDrink:
            Text("Tap to log. Hold any drink for Standard, Large, or Other (mL).")
                .foregroundStyle(AppColors.textSecondary)
            if let active = appState.activeEvent {
                guideLink("Show me where to log a drink", to: .guidedEvent(active.id, .drinks))
            } else {
                startNightLink(for: .drinks)
            }
        }
    }

    private func startNightLink(for target: EventGuideTarget) -> some View {
        Button { newNightGuide = target } label: {
            Label("Show me how to start a night", systemImage: "arrow.up.right")
        }
        .tint(AppColors.accent)
    }

    private func guideLink(_ title: LocalizedStringKey, to route: Route) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: "arrow.up.right")
        }
        .tint(AppColors.accent)
    }

    private var celebration: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 70))
                .foregroundStyle(AppColors.accentWarm)
                .frame(width: 126, height: 126)
                .background(AppColors.accentDim, in: Circle())
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkle")
                        .font(.title2)
                        .foregroundStyle(AppColors.accentWarm)
                }
                .accessibilityHidden(true)
            Text("You did it!")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($celebrationFocused)
            Text("Your setup is complete. Tracksip is ready for your next night out.")
                .foregroundStyle(AppColors.textSecondary)
            action("Done") { dismiss() }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(24)
        .premiumCard(radius: 24, tint: AppColors.accent, tintOpacity: 0.12)
        .onAppear { celebrationFocused = true }
    }

    private func action(_ title: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.accent)
        .foregroundStyle(.black)
    }

    private func complete(_ step: SetupStep) {
        let wasIncomplete = !SetupStep.remaining(in: progress).isEmpty
        let updatedProgress = progress | step.flag
        let remaining = SetupStep.remaining(in: updatedProgress)
        let justFinished = wasIncomplete && remaining.isEmpty

        withAnimation(reduceMotion ? nil : .spring(duration: 0.42)) {
            progress = updatedProgress
            expandedStep = remaining.first
            if justFinished { showCelebration = true }
        }
        Haptics.shared.play(justFinished ? .success : .selection)
    }
}

extension View {
    func guideHighlight(_ isHighlighted: Bool, radius: CGFloat = 10) -> some View {
        overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(AppColors.accentWarm, lineWidth: 2)
                    .padding(-4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
