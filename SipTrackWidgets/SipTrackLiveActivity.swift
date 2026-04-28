import ActivityKit
import SwiftUI
import WidgetKit

struct SipTrackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SipTrackActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(hex: "#0D0D18"))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.3f%%", context.state.bac))
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: context.state.stageColorHex))
                        Text(context.state.stageName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: context.state.stageColorHex))
                    }
                    .padding(.leading, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(context.state.drinkCount)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        Text("drink\(context.state.drinkCount == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.trailing, 2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        ForEach(context.state.quickDrinks.prefix(4)) { drink in
                            drinkButton(drink: drink, eventId: context.state.eventId)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: context.state.stageColorHex))
                        .frame(width: 5, height: 5)
                    Text(String(format: "%.3f", context.state.bac))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: context.state.stageColorHex))
                }
            } compactTrailing: {
                HStack(spacing: 3) {
                    Image(systemName: "wineglass.fill")
                        .font(.system(size: 10))
                    Text("\(context.state.drinkCount)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
            } minimal: {
                Text(String(format: "%.2f", context.state.bac))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: context.state.stageColorHex))
            }
            .contentMargins(.horizontal, 12, for: .expanded)
            .contentMargins(.top, 10, for: .expanded)
        }
    }

    @ViewBuilder
    private func drinkButton(drink: SipTrackActivityAttributes.QuickDrink, eventId: String) -> some View {
        if let url = URL(string: "siptrack://drink?type=\(drink.id)&event=\(eventId)") {
            Link(destination: url) {
                VStack(spacing: 4) {
                    Image(systemName: drink.symbol)
                        .font(.system(size: 17))
                    Text(drink.name)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(.white.opacity(0.12))
                .cornerRadius(9)
            }
        }
    }
}

// MARK: - Lock screen view

private struct LockScreenView: View {
    let context: ActivityViewContext<SipTrackActivityAttributes>

    private var stageColor: Color { Color(hex: context.state.stageColorHex) }
    private var barFill: Double { min(1, max(0, context.state.bac / 0.50)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            bacSection
            progressBar
            statsRow
            Divider()
                .background(.white.opacity(0.12))
                .padding(.horizontal, 16)
                .padding(.top, 12)
            drinkButtons
        }
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                Text(context.attributes.eventName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var bacSection: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.3f%%", context.state.bac))
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(stageColor)
            Text(context.state.stageName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(stageColor.opacity(0.85))
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 3)
                    .fill(stageColor)
                    .frame(width: geo.size.width * barFill)
            }
            .frame(height: 4)
        }
        .frame(height: 4)
        .padding(.horizontal, 16)
    }

    private var statsRow: some View {
        let h = context.state.elapsedMinutes / 60
        let m = context.state.elapsedMinutes % 60

        return HStack(spacing: 14) {
            HStack(spacing: 4) {
                Image(systemName: "wineglass.fill")
                    .font(.system(size: 10))
                Text("\(context.state.drinkCount) drink\(context.state.drinkCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
            }
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10))
                Text(h > 0 ? "\(h)h \(m)m" : "\(m)m")
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(.white.opacity(0.55))
        .padding(.top, 7)
    }

    private var drinkButtons: some View {
        HStack(spacing: 8) {
            ForEach(context.state.quickDrinks.prefix(4)) { drink in
                if let url = URL(string: "siptrack://drink?type=\(drink.id)&event=\(context.state.eventId)") {
                    Link(destination: url) {
                        VStack(spacing: 5) {
                            Image(systemName: drink.symbol)
                                .font(.system(size: 20))
                            Text(drink.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(.white.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
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
