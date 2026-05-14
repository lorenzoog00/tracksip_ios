import SwiftUI

struct WatchHomeView: View {

    @ObservedObject var state = WatchState.shared
    @State private var showAddDrink = false
    @State private var showEndConfirm = false

    var body: some View {
        if state.hasActiveEvent {
            activeView
        } else {
            idleView
        }
    }

    // MARK: - No active event

    private var idleView: some View {
        VStack(spacing: 10) {
            Image(systemName: "wineglass.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color(red: 0.83, green: 0.68, blue: 0.33))

            Text("TrackSip")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            if !state.isPhoneReachable {
                Text("iPhone not connected")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }

            Button {
                state.startEvent()
            } label: {
                if state.isSending {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Start Night")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.83, green: 0.68, blue: 0.33))
            .disabled(state.isSending || !state.isPhoneReachable)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Active event

    private var activeView: some View {
        VStack(spacing: 0) {
            // Event name + live dot
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(red: 0.22, green: 0.85, blue: 0.50))
                    .frame(width: 6, height: 6)
                Text(state.eventName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            .padding(.bottom, 4)

            // BAC number
            Text(String(format: "%.3f%%", state.currentBAC))
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(state.bacColor)
                .minimumScaleFactor(0.6)

            // Stage name
            Text(state.stageName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state.bacColor.opacity(0.8))
                .padding(.bottom, 6)

            // Drink count
            HStack(spacing: 4) {
                Image(systemName: "wineglass.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.83, green: 0.68, blue: 0.33))
                Text("\(state.drinkCount) drink\(state.drinkCount == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.bottom, 8)

            // Action buttons
            HStack(spacing: 6) {
                Button {
                    showAddDrink = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.83, green: 0.68, blue: 0.33))

                Button {
                    state.addWater()
                } label: {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)

                Button {
                    showEndConfirm = true
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red.opacity(0.8))
            }
        }
        .sheet(isPresented: $showAddDrink) {
            WatchAddDrinkView(state: state, isPresented: $showAddDrink)
        }
        .confirmationDialog("End night?", isPresented: $showEndConfirm) {
            Button("End Night", role: .destructive) { state.endEvent() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
