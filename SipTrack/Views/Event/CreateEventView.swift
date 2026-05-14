import SwiftUI

struct CreateEventView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name          = ""
    @State private var drivingMode   = false
    @State private var bacLimit      = 0.08
    @State private var targetBAC: Double? = nil
    @State private var startTime     = Date()
    @State private var customStart   = false
    @State private var stomachState: StomachState = .empty
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {

                            // Event name
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Event Name (optional)", systemImage: "pencil")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.textSecondary)
                                TextField("e.g. Friday Rooftop", text: $name)
                                    .focused($nameFocused)
                                    .submitLabel(.done)
                                    .onSubmit { nameFocused = false }
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

                            Divider().background(AppColors.border)

                            // Tonight's Ceiling — classy meter, no emojis
                            GoalCeilingMeter(targetBAC: $targetBAC)

                            Divider().background(AppColors.border)

                            // Stomach state
                            VStack(alignment: .leading, spacing: 8) {
                                Text("How full is your stomach?")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                HStack(spacing: 10) {
                                    ForEach([StomachState.empty, .snack, .fullMeal], id: \.self) { state in
                                        Button {
                                            stomachState = state
                                        } label: {
                                            VStack(spacing: 4) {
                                                Text(state.emoji)
                                                    .font(.title2)
                                                Text(state.displayName)
                                                    .font(.caption2)
                                                    .fontWeight(.medium)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(stomachState == state ? AppColors.accent.opacity(0.15) : Color(.systemGray6))
                                            .foregroundStyle(stomachState == state ? AppColors.accent : .secondary)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(stomachState == state ? AppColors.accent : Color.clear, lineWidth: 1.5)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

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

                            Color.clear.frame(height: 8)
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)

                    // Sticky bottom CTA — outside the ScrollView so the keyboard
                    // can't push the form contents off the top of the screen.
                    Button {
                        let event = appState.createEvent(
                            name: name.isEmpty ? nil : name,
                            drivingMode: drivingMode,
                            bacLimit: drivingMode ? bacLimit : nil,
                            targetBAC: targetBAC,
                            startTime: customStart ? startTime : Date(),
                            stomachState: stomachState
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
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(AppColors.background)
                    .overlay(Rectangle().frame(height: 0.5).foregroundStyle(AppColors.border), alignment: .top)
                }
            }
            .navigationTitle("New Night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { nameFocused = false }
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
        }
    }
}

// MARK: - Tonight's Ceiling Meter
//
// Classy ceiling picker. A horizontal track is painted with the same stage
// colours used by the live BAC gauge (IntoxicationStage), and the user drags
// a thumb to pick a BAC ceiling for the night. Drag below the first tick
// turns the ceiling off.

private struct GoalCeilingMeter: View {
    @Binding var targetBAC: Double?

    private let stages: [IntoxicationStage] = Array(IntoxicationStage.all.prefix(5)) // Sober..Drunk
    private let minBAC: Double = 0.0
    private let maxBAC: Double = 0.20
    private let snap:   Double = 0.005

    private var currentStage: IntoxicationStage? {
        targetBAC.map { IntoxicationStage.stage(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Text("Tonight's Ceiling")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                if let t = targetBAC, let s = currentStage {
                    HStack(spacing: 6) {
                        Text(s.name.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(s.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(s.color.opacity(0.14))
                            .cornerRadius(4)
                        Text(String(format: "%.2f%%", t))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.text)
                    }
                } else {
                    Text("OFF")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppColors.surface)
                        .cornerRadius(4)
                }
            }

            // Track
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // Stage-coloured zones, width-proportional to each stage's BAC span
                    HStack(spacing: 0) {
                        ForEach(Array(stages.enumerated()), id: \.offset) { _, s in
                            let lo = max(s.minBAC, minBAC)
                            let hi = min(s.maxBAC, maxBAC)
                            let frac = max(0, (hi - lo) / (maxBAC - minBAC))
                            Rectangle()
                                .fill(s.color.opacity(targetBAC == nil ? 0.18 : 0.32))
                                .frame(width: max(0, w * frac))
                        }
                    }
                    .frame(height: 12)
                    .clipShape(Capsule())

                    // Thumb
                    if let t = targetBAC {
                        let frac = min(1, max(0, (t - minBAC) / (maxBAC - minBAC)))
                        Circle()
                            .fill(currentStage?.color ?? AppColors.accent)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(.white.opacity(0.95), lineWidth: 2))
                            .shadow(color: (currentStage?.color ?? .black).opacity(0.45),
                                    radius: 6, x: 0, y: 2)
                            .offset(x: max(-10, min(w - 10, w * frac - 10)))
                            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: t)
                    } else {
                        // "Tap to enable" hint thumb at start
                        Circle()
                            .stroke(AppColors.border, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .frame(width: 18, height: 18)
                            .offset(x: -9)
                    }
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let p = max(0, min(1, v.location.x / w))
                            let raw = minBAC + p * (maxBAC - minBAC)
                            let snapped = (raw / snap).rounded() * snap
                            targetBAC = snapped < snap ? nil : snapped
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                )
            }
            .frame(height: 22)

            // Stage labels
            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { _, s in
                    Text(s.name.uppercased())
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(
                            currentStage?.name == s.name ? s.color : AppColors.textTertiary.opacity(0.75)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 8) {
                if targetBAC == nil {
                    Button {
                        targetBAC = 0.05
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text("Set a ceiling")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text("Drag the bar to pick a max")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                } else {
                    Text("We'll warn before any drink that would cross it.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                    Button {
                        targetBAC = nil
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
