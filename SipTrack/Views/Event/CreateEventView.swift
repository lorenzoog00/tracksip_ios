import SwiftUI

struct CreateEventView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name        = ""
    @State private var drivingMode = false
    @State private var bacLimit    = 0.08
    @State private var startTime   = Date()
    @State private var customStart = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                VStack(spacing: 24) {

                    // Event name
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Event Name (optional)", systemImage: "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        TextField("e.g. Friday Rooftop", text: $name)
                            .padding(12)
                            .background(AppColors.surface)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                            .foregroundStyle(AppColors.text)
                    }

                    Divider().background(AppColors.border)

                    // Start time
                    VStack(spacing: 10) {
                        Toggle(isOn: $customStart.animation(.easeInOut(duration: 0.2))) {
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .foregroundStyle(customStart ? AppColors.accent : AppColors.textSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Custom Start Time")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(AppColors.text)
                                    Text("Started drinking earlier tonight")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                        }
                        .tint(AppColors.accent)

                        if customStart {
                            DatePicker(
                                "",
                                selection: $startTime,
                                in: ...Date(),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .padding(12)
                            .background(AppColors.surface)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                            .tint(AppColors.accent)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: customStart)

                    Divider().background(AppColors.border)

                    // Driving mode
                    VStack(spacing: 12) {
                        Toggle(isOn: $drivingMode) {
                            HStack(spacing: 10) {
                                Image(systemName: "car.fill")
                                    .foregroundStyle(drivingMode ? AppColors.danger : AppColors.textSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Driving Mode")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(AppColors.text)
                                    Text("Warnings when approaching your BAC limit")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                        }
                        .tint(AppColors.danger)

                        if drivingMode {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("BAC Limit")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.textSecondary)
                                Picker("BAC Limit", selection: $bacLimit) {
                                    Text("0.05%").tag(0.05)
                                    Text("0.08%").tag(0.08)
                                }
                                .pickerStyle(.segmented)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: drivingMode)

                    if appState.activeEvent != nil {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppColors.accent)
                            Text("You already have an active night. End it first.")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(12)
                        .background(AppColors.accentDim)
                        .cornerRadius(10)
                    }

                    Spacer()

                    Button {
                        let event = appState.createEvent(
                            name: name.isEmpty ? nil : name,
                            drivingMode: drivingMode,
                            bacLimit: drivingMode ? bacLimit : nil,
                            startTime: customStart ? startTime : Date()
                        )
                        appState.pendingEventRouteId = event.id
                        dismiss()
                    } label: {
                        Text("Start Night")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(appState.activeEvent == nil ? AppColors.accent : AppColors.border)
                            .foregroundStyle(appState.activeEvent == nil ? Color.black : AppColors.textTertiary)
                            .cornerRadius(14)
                    }
                    .disabled(appState.activeEvent != nil)
                }
                .padding()
            }
            .navigationTitle("New Night")
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
