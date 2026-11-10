import ActivityKit
import AppIntents
import SipTrackActivityKit
import SwiftUI
import WidgetKit

struct SipTrackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SipTrackActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(hex: "#0A0A14"))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "%.3f%%", context.state.bac))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: context.state.stageColorHex))
                        Text(context.state.stageName.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Color(hex: context.state.stageColorHex).opacity(0.7))
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(context.state.drinkCount)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text(context.state.drinkCount == 1 ? "drink" : "drinks")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                        if let balance = context.state.hydrationBalance {
                            HydrationBadge(balance: balance, size: 10)
                        }
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        ForEach(context.state.quickDrinks.prefix(3)) { drink in
                            islandDrinkButton(drink: drink, eventId: context.state.eventId)
                        }
                        islandWaterButton(eventId: context.state.eventId)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(hex: context.state.stageColorHex))
                        .frame(width: 5, height: 5)
                    Text(String(format: "%.3f", context.state.bac))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: context.state.stageColorHex))
                }
            } compactTrailing: {
                HStack(spacing: 2) {
                    Image(systemName: "wineglass.fill")
                        .font(.system(size: 9))
                    Text("\(context.state.drinkCount)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color(hex: context.state.stageColorHex))
            } minimal: {
                Circle()
                    .fill(Color(hex: context.state.stageColorHex))
                    .frame(width: 8, height: 8)
            }
            .contentMargins(.horizontal, 10, for: .expanded)
            .contentMargins(.top, 8, for: .expanded)
        }
    }

    // Button(intent:) runs the intent in the background, so one tap logs the
    // drink without opening the app (the old Link opened it every time).
    private func islandDrinkButton(drink: SipTrackActivityAttributes.QuickDrink, eventId: String) -> some View {
        Button(intent: AddDrinkFromLiveActivityIntent(drinkTypeId: drink.id, eventId: eventId)) {
            HStack(spacing: 4) {
                Image(systemName: drink.symbol)
                    .font(.system(size: 13, weight: .medium))
                Text(drink.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func islandWaterButton(eventId: String) -> some View {
        Button(intent: AddWaterFromLiveActivityIntent(eventId: eventId)) {
            Image(systemName: "drop.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#40AAFF"))
                .frame(width: 44, height: 38)
                .background(Color(hex: "#40AAFF").opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: "#40AAFF").opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add water")
    }
}

// MARK: - Lock screen view

private struct LockScreenView: View {
    let context: ActivityViewContext<SipTrackActivityAttributes>

    var body: some View {
        LockScreenContent(
            bac: context.state.bac,
            context: context
        )
    }
}

private struct LockScreenContent: View {
    let bac: Double
    let context: ActivityViewContext<SipTrackActivityAttributes>

    private var stageColor: Color { Color(hex: context.state.stageColorHex) }
    private var barFill: Double { min(1.0, max(0.0, bac / 0.25)) }

    // Laid out for reading at a glance on a dark lock screen: what you're
    // drinking, BAC, the night's counts and the buttons, in large type with
    // nothing under 13 pt. The lock screen caps the card at about 160 pt tall,
    // so each row earns its height.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Row 1 — what you're drinking and for how long. A lock-screen tap
            // shows "Red Wine added" here for a few seconds instead.
            HStack(spacing: 6) {
                if let action = context.state.actionText {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(action)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                } else if let name = context.state.currentDrinkName,
                          let started = context.state.currentDrinkStartedAt {
                    Image(systemName: context.state.currentDrinkSymbol ?? "wineglass.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    // Time with this drink, counting up on its own.
                    Text(started, style: .timer)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 72, alignment: .trailing)
                } else {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 14))
                    Text(context.attributes.eventName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
            }
            .foregroundStyle(stageColor)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Row 2 — BAC (hero) with stage, drinks and hydration beside it.
            HStack(alignment: .center, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text(String(format: "%.3f", bac))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(stageColor)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text("%")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(stageColor.opacity(0.6))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(context.state.stageName.uppercased())
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(stageColor)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "wineglass.fill").font(.system(size: 13))
                            Text("\(context.state.drinkCount)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .accessibilityLabel("\(context.state.drinkCount) drinks")
                        if let balance = context.state.hydrationBalance {
                            HydrationBadge(balance: balance, size: 16)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            // Row 3 — the current drink's bar: fills over its drinking time on
            // its own (ProgressView(timerInterval:) needs no updates). Falls back
            // to the BAC bar before the first drink.
            Group {
                if let started = context.state.currentDrinkStartedAt {
                    let minutes = Double(context.state.currentDrinkMinutes ?? 20)
                    ProgressView(
                        timerInterval: started...started.addingTimeInterval(minutes * 60),
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                    .progressViewStyle(.linear)
                    .tint(stageColor)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1)).frame(height: 4)
                            Capsule().fill(stageColor)
                                .frame(width: max(4, geo.size.width * barFill), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)

            // Row 4 — one-tap buttons
            HStack(spacing: 8) {
                ForEach(context.state.quickDrinks.prefix(3)) { drink in
                    lockDrinkButton(drink)
                }
                lockWaterButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func lockDrinkButton(_ drink: SipTrackActivityAttributes.QuickDrink) -> some View {
        Button(intent: AddDrinkFromLiveActivityIntent(drinkTypeId: drink.id, eventId: context.state.eventId)) {
            HStack(spacing: 6) {
                Image(systemName: drink.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(stageColor)
                Text(drink.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(.white.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var lockWaterButton: some View {
        Button(intent: AddWaterFromLiveActivityIntent(eventId: context.state.eventId)) {
            Image(systemName: "drop.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "#40AAFF"))
                .frame(width: 50, height: 42)
                .background(Color(hex: "#40AAFF").opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(hex: "#40AAFF").opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add water")
    }
}

// MARK: - Hydration

/// Glasses of water minus drinks, coloured like the in-app Hydration stat:
/// red when behind, white when even, green when ahead.
private struct HydrationBadge: View {
    let balance: Int
    let size: CGFloat

    private var color: Color {
        switch balance {
        case ..<0: return Color(hex: "#FF4757")
        case 0: return .white.opacity(0.8)
        default: return Color(hex: "#2ED573")
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "drop.fill").font(.system(size: size - 2))
            Text(balance > 0 ? "+\(balance)" : "\(balance)")
                .font(.system(size: size, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(color)
        .accessibilityLabel("Hydration \(balance)")
    }
}

// MARK: - Color hex helper (local to widget extension)

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
