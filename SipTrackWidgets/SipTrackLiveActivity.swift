import ActivityKit
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
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        ForEach(context.state.quickDrinks.prefix(4)) { drink in
                            islandDrinkButton(drink: drink, eventId: context.state.eventId)
                        }
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

    @ViewBuilder
    private func islandDrinkButton(drink: SipTrackActivityAttributes.QuickDrink, eventId: String) -> some View {
        if let url = URL(string: "siptrack://drink?type=\(drink.id)&event=\(eventId)") {
            Link(destination: url) {
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
        }
    }
}

// MARK: - Lock screen view

private struct LockScreenView: View {
    let context: ActivityViewContext<SipTrackActivityAttributes>

    private var stageColor: Color { Color(hex: context.state.stageColorHex) }
    private var barFill: Double { min(1.0, max(0.0, context.state.bac / 0.25)) }
    private var elapsedText: String {
        let h = context.state.elapsedMinutes / 60
        let m = context.state.elapsedMinutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Row 1 — event name + LIVE badge
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(context.attributes.eventName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 4, height: 4)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Row 2 — BAC (hero) + stage + stats
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                // BAC number — the hero
                Text(String(format: "%.3f", context.state.bac))
                    .font(.system(size: 46, weight: .bold, design: .monospaced))
                    .foregroundStyle(stageColor)
                Text("%")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(stageColor.opacity(0.5))
                    .padding(.bottom, 4)

                Spacer()

                // Stage + stats stacked right
                VStack(alignment: .trailing, spacing: 3) {
                    Text(context.state.stageName.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(stageColor.opacity(0.85))
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "wineglass.fill").font(.system(size: 9))
                            Text("\(context.state.drinkCount)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "clock").font(.system(size: 9))
                            Text(elapsedText).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            // Row 3 — progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08)).frame(height: 3)
                    Capsule().fill(
                        LinearGradient(colors: [stageColor.opacity(0.7), stageColor],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(3, geo.size.width * barFill), height: 3)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            // Row 4 — drink buttons
            HStack(spacing: 7) {
                ForEach(context.state.quickDrinks.prefix(3)) { drink in
                    lockDrinkButton(drink)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func lockDrinkButton(_ drink: SipTrackActivityAttributes.QuickDrink) -> some View {
        if let url = URL(string: "siptrack://drink?type=\(drink.id)&event=\(context.state.eventId)") {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: drink.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(stageColor)
                    Text(drink.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
            }
        }
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
