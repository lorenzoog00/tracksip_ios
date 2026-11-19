import SwiftUI

extension Reaction {
    /// The colour of this reaction's particle burst.
    var tint: Color {
        switch self {
        case .beer: return AppColors.accent
        case .fire: return Color(hex: "#FF6B35")
        case .laugh: return AppColors.accentWarm
        case .woozy: return Color(hex: "#7BED9F")
        case .water: return AppColors.water
        case .heart: return Color(hex: "#FF4D6D")
        }
    }

    /// What VoiceOver says for it.
    var spokenName: String {
        switch self {
        case .beer: return "Cheers"
        case .fire: return "Fire"
        case .laugh: return "Laughing"
        case .woozy: return "Woozy"
        case .water: return "Water"
        case .heart: return "Love"
        }
    }
}

/// Fixed geometry of the picker, so a finger can be matched to an emoji without
/// measuring the views.
nonisolated enum ReactionPickerMetrics {
    static let item: CGFloat = 40
    static let spacing: CGFloat = 4
    static let padding: CGFloat = 6
    static let width: CGFloat = padding * 2 + item * 6 + spacing * 5
    static let height: CGFloat = item + padding * 2

    /// Which of the six sits under `x`, measured from the picker's leading edge.
    static func index(atX x: CGFloat) -> Int? {
        guard x >= 0, x <= width else { return nil }
        let slot = item + spacing
        let i = Int(((x - padding + spacing / 2) / slot).rounded(.down))
        return min(max(i, 0), 5)
    }
}

// MARK: - Picker

/// The six reactions in a row. Each one pops in with a 30 ms stagger; `hovered`
/// (the one under a dragging finger) grows and lifts. Tapping one picks it.
struct ReactionPicker: View {
    let selected: Reaction?
    let hovered: Reaction?
    let onPick: (Reaction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    init(selected: Reaction?, hovered: Reaction? = nil, onPick: @escaping (Reaction) -> Void) {
        self.selected = selected
        self.hovered = hovered
        self.onPick = onPick
    }

    var body: some View {
        HStack(spacing: ReactionPickerMetrics.spacing) {
            ForEach(Array(Reaction.allCases.enumerated()), id: \.element) { index, reaction in
                Button {
                    onPick(reaction)
                } label: {
                    emoji(reaction, index: index)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reaction.spokenName)
                .accessibilityAddTraits(reaction == selected ? .isSelected : [])
            }
        }
        .padding(ReactionPickerMetrics.padding)
        .background {
            Capsule()
                .fill(AppColors.surfaceElevated)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        }
        .overlay {
            Capsule().stroke(AppColors.rimLight, lineWidth: 1)
        }
        .fixedSize()
        .onAppear { appeared = true }
    }

    private func emoji(_ reaction: Reaction, index: Int) -> some View {
        let isHovered = hovered == reaction
        let isSelected = selected == reaction
        return Text(reaction.emoji)
            .font(.system(size: 26))
            .frame(width: ReactionPickerMetrics.item, height: ReactionPickerMetrics.item)
            .background {
                Circle().fill(isSelected ? AppColors.accentDim : Color.clear)
            }
            .overlay {
                Circle().stroke(isSelected ? AppColors.accent.opacity(0.7) : Color.clear, lineWidth: 1.5)
            }
            .scaleEffect(scale(isHovered: isHovered))
            .offset(y: offset(isHovered: isHovered))
            .opacity(appeared ? 1 : 0)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.38, dampingFraction: 0.6).delay(Double(index) * 0.03),
                value: appeared
            )
            .animation(
                reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.25, dampingFraction: 0.6),
                value: hovered
            )
            .contentShape(Circle())
    }

    private func scale(isHovered: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        guard appeared else { return 0.3 }
        return isHovered ? 1.5 : 1
    }

    private func offset(isHovered: Bool) -> CGFloat {
        if reduceMotion { return 0 }
        guard appeared else { return 14 }
        return isHovered ? -12 : 0
    }
}

// MARK: - Bar

/// Counts for the reactions people used, mine highlighted, and a `+` that fans out
/// the picker. Tap a pill to react with it (tap mine to take it back). Long-press
/// the `+` or a pill and slide to an emoji, release to react; a plain tap on `+`
/// opens the same row to tap.
struct ReactionBar: View {
    @ObservedObject private var store: NightThreadStore
    let canReact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerOpen = false
    @State private var hovered: Reaction?
    @State private var popping: Reaction?
    @State private var burst: Reaction?
    @State private var burstID = 0

    private static let space = "reactionBar"
    private static let pillHeight: CGFloat = 32
    /// Gap between the bar's top and the picker's bottom.
    private static let pickerGap: CGFloat = 6

    init(store: NightThreadStore, canReact: Bool) {
        _store = ObservedObject(wrappedValue: store)
        self.canReact = canReact
    }

    var body: some View {
        let counts = store.summary.counts
        let shown = Reaction.allCases.filter { (counts[$0] ?? 0) > 0 }
        HStack(spacing: 6) {
            ForEach(shown) { reaction in
                pill(reaction, count: counts[reaction] ?? 0)
                    .transition(pillTransition)
            }
            if canReact {
                plusButton
            } else if shown.isEmpty {
                Text("No reactions yet")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(height: Self.pillHeight)
            }
        }
        .animation(changeAnimation, value: counts)
        .animation(changeAnimation, value: store.myReaction)
        .coordinateSpace(NamedCoordinateSpace.named(Self.space))
        .overlay(alignment: .bottomLeading) {
            if pickerOpen && canReact {
                ReactionPicker(selected: store.myReaction, hovered: hovered) { reaction in
                    pick(reaction)
                }
                .offset(y: -(Self.pillHeight + Self.pickerGap))
                .transition(pickerTransition)
            }
        }
        .onChange(of: canReact) { _, can in
            if !can { closePicker() }
        }
    }

    // MARK: Pieces

    private func pill(_ reaction: Reaction, count: Int) -> some View {
        let mine = store.myReaction == reaction
        return HStack(spacing: 4) {
            Text(reaction.emoji)
                .font(.system(size: 15))
                .scaleEffect(popping == reaction ? 1.35 : 1)
            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(mine ? AppColors.accent : AppColors.text)
                .contentTransition(.numericText(value: Double(count)))
        }
        .padding(.horizontal, 10)
        .frame(height: Self.pillHeight)
        .background {
            Capsule().fill(mine ? AppColors.accentDim : Color.white.opacity(0.06))
        }
        .overlay {
            Capsule().stroke(mine ? AppColors.accent.opacity(0.6) : AppColors.border, lineWidth: 1)
        }
        .overlay {
            if burst == reaction {
                ReactionBurst(color: reaction.tint)
                    .id(burstID)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Capsule())
        .gesture(fanGesture { react(reaction) }, including: canReact ? .all : .subviews)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reaction.spokenName), \(count)")
        .accessibilityValue(mine ? "Your reaction" : "")
        .accessibilityAddTraits(canReact ? .isButton : [])
        .accessibilityAction {
            if canReact { react(reaction) }
        }
        .accessibilityAction(named: "More reactions") {
            if canReact { openPicker() }
        }
    }

    private var plusButton: some View {
        Image(systemName: "plus")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(pickerOpen ? AppColors.accent : AppColors.textSecondary)
            .rotationEffect(.degrees(pickerOpen ? 45 : 0))
            .frame(width: Self.pillHeight, height: Self.pillHeight)
            .background {
                Circle().fill(pickerOpen ? AppColors.accentDim : Color.white.opacity(0.06))
            }
            .overlay {
                Circle().stroke(pickerOpen ? AppColors.accent.opacity(0.6) : AppColors.border, lineWidth: 1)
            }
            .contentShape(Circle())
            .animation(changeAnimation, value: pickerOpen)
            .gesture(fanGesture { togglePicker() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pickerOpen ? "Close reactions" : "Add reaction")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { togglePicker() }
    }

    // MARK: Gestures

    /// Long-press opens the fan and tracks the finger; releasing on an emoji reacts,
    /// releasing anywhere else leaves the fan open to tap. A quick tap runs `onTap`.
    private func fanGesture(onTap: @escaping () -> Void) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0,
                                           coordinateSpace: NamedCoordinateSpace.named(Self.space)))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !pickerOpen { openPicker() }
                if let drag { hover(Self.reaction(at: drag.location)) }
            }
            .onEnded { value in
                guard case .second(true, let drag) = value else { return }
                if let drag, let reaction = Self.reaction(at: drag.location) {
                    pick(reaction)
                } else {
                    hovered = nil
                }
            }
            .exclusively(before: TapGesture().onEnded { onTap() })
    }

    /// The emoji under a point in the bar's space. The picker sits right above the bar,
    /// starting at its leading edge; only a finger that has moved up off the bar counts,
    /// so a long-press that is simply let go never reacts by accident.
    private static func reaction(at point: CGPoint) -> Reaction? {
        let pickerBottom = -pickerGap
        guard point.y < pickerBottom + 4,
              point.y > pickerBottom - ReactionPickerMetrics.height - 70,
              let index = ReactionPickerMetrics.index(atX: point.x)
        else { return nil }
        return Reaction.allCases[index]
    }

    // MARK: Actions

    private func hover(_ reaction: Reaction?) {
        guard reaction != hovered else { return }
        hovered = reaction
        if reaction != nil { Haptics.shared.play(.selection) }
    }

    private func togglePicker() {
        if pickerOpen { closePicker() } else { openPicker() }
    }

    private func openPicker() {
        guard canReact, !pickerOpen else { return }
        Haptics.shared.play(.light)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.72)) {
            pickerOpen = true
        }
    }

    private func closePicker() {
        hovered = nil
        guard pickerOpen else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.28, dampingFraction: 0.85)) {
            pickerOpen = false
        }
    }

    private func pick(_ reaction: Reaction) {
        closePicker()
        react(reaction)
    }

    /// Same reaction takes it back; another replaces it. The store is optimistic, so
    /// the counts move at once and the bar animates them.
    private func react(_ reaction: Reaction) {
        guard canReact else { return }
        let adding = store.myReaction != reaction
        Haptics.shared.play(.selection)
        if adding && !reduceMotion {
            pop(reaction)
            burstID &+= 1
            burst = reaction
            let id = burstID
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                if burstID == id { burst = nil }
            }
        }
        Task { await store.react(reaction) }
    }

    /// 1 → 1.35 → 1.
    private func pop(_ reaction: Reaction) {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
            popping = reaction
        }
        Task {
            try? await Task.sleep(for: .milliseconds(170))
            guard popping == reaction else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                popping = nil
            }
        }
    }

    // MARK: Motion

    private var changeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.68)
    }

    /// Switching reactions: the old pill shrinks out while the new one springs in.
    private var pillTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity)
    }

    private var pickerTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity)
    }
}

// MARK: - Burst

/// A short ring of particles flying out of a reaction, in its colour. Only shown
/// with motion on.
struct ReactionBurst: View {
    let color: Color
    @State private var fired = false

    init(color: Color) {
        self.color = color
    }

    private static let particles = 10
    private static let distance: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(fired ? 0 : 0.7), lineWidth: 1.5)
                .frame(width: 30, height: 30)
                .scaleEffect(fired ? 1.7 : 0.4)
            ForEach(0..<Self.particles, id: \.self) { i in
                let angle = Double(i) / Double(Self.particles) * 2 * Double.pi
                let size: CGFloat = i.isMultiple(of: 2) ? 5 : 3.5
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .offset(x: fired ? CGFloat(cos(angle)) * Self.distance : 0,
                            y: fired ? CGFloat(sin(angle)) * Self.distance : 0)
                    .scaleEffect(fired ? 0.3 : 1)
                    .opacity(fired ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { fired = true }
        }
        .accessibilityHidden(true)
    }
}
