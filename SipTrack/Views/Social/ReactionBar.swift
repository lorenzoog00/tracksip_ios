import SwiftUI
import Combine

extension Reaction {
    /// The colour of this reaction's particle burst.
    var tint: Color {
        switch self {
        case .beer: return AppColors.accent
        case .water: return AppColors.water
        }
    }

    /// What VoiceOver says for it.
    var spokenName: String {
        switch self {
        case .beer: return "Cheers"
        case .water: return "Water"
        }
    }
}

/// Which reaction pills fit on a card: the most used, mine always among them.
nonisolated enum ReactionBarLayout {
    static let maxPills = 3

    /// Up to `limit` reactions in `Reaction.allCases` order, picked by count (ties by
    /// `allCases` order) with `mine` swapped in if it would miss the cut; `hidden` is
    /// how many reactions the rest add up to.
    static func visible(counts: [Reaction: Int], mine: Reaction?,
                        limit: Int = maxPills) -> (shown: [Reaction], hidden: Int) {
        let used = Reaction.allCases.filter { (counts[$0] ?? 0) > 0 }
        let ranked = used.enumerated()
            .sorted { a, b in
                let ca = counts[a.element] ?? 0
                let cb = counts[b.element] ?? 0
                return ca != cb ? ca > cb : a.offset < b.offset
            }
            .map { $0.element }
        var picked = Array(ranked.prefix(max(0, limit)))
        if let mine, used.contains(mine), !picked.contains(mine), !picked.isEmpty {
            picked[picked.count - 1] = mine
        }
        let shown = used.filter { picked.contains($0) }
        let hidden = used.filter { !picked.contains($0) }.reduce(0) { $0 + (counts[$1] ?? 0) }
        return (shown, hidden)
    }
}

/// Fixed geometry of the picker, so a finger can be matched to an emoji without
/// measuring the views. Each slot is a 44 pt hit target around a 40 pt emoji.
nonisolated enum ReactionPickerMetrics {
    static let item: CGFloat = 44
    static let visual: CGFloat = 40
    static let spacing: CGFloat = 0
    static let padding: CGFloat = 4
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

/// At most one picker open in the whole feed. Opening one closes any other; the feed
/// closes it on scroll and on a tap anywhere else.
@MainActor
final class ReactionPickerFocus: ObservableObject {
    static let shared = ReactionPickerFocus()

    @Published private(set) var openKey: NightKey?

    var isOpen: Bool { openKey != nil }

    func open(_ key: NightKey) {
        if openKey != key { openKey = key }
    }

    func close() {
        if openKey != nil { openKey = nil }
    }

    func close(_ key: NightKey) {
        if openKey == key { openKey = nil }
    }

    /// Closes with the standard fade/spring.
    static func dismiss(reduceMotion: Bool) {
        guard shared.isOpen else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.28, dampingFraction: 0.85)) {
            shared.close()
        }
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
            .frame(width: ReactionPickerMetrics.visual, height: ReactionPickerMetrics.visual)
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
            // 44 pt hit target around the 40 pt emoji.
            .frame(width: ReactionPickerMetrics.item, height: ReactionPickerMetrics.item)
            .contentShape(Rectangle())
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

/// The three most used reactions (mine always among them), mine highlighted, and a
/// `+` that fans out the picker; when more reactions are hidden the `+` reads "+N".
/// Tap a pill to react with it (tap mine to take it back). Long-press the `+` or a
/// pill and slide to an emoji, release to react; a plain tap on `+` opens the same
/// row to tap.
struct ReactionBar: View {
    @ObservedObject private var store: NightThreadStore
    @ObservedObject private var focus = ReactionPickerFocus.shared
    let canReact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The emoji under a dragging finger. Resets by itself when the drag ends or is
    /// cancelled (scroll took over, view went away).
    @GestureState private var hovered: Reaction?
    @State private var popping: Reaction?
    @State private var burst: Reaction?
    @State private var burstID = 0

    private static let space = "reactionBar"
    /// What you see.
    private static let pillHeight: CGFloat = 32
    /// What you can tap.
    private static let hitHeight: CGFloat = 44
    /// Horizontal hit padding around each pill; two neighbours make the 6 pt gap.
    private static let pillHitInset: CGFloat = 3
    /// Gap between the pills' visible top and the picker's bottom.
    private static let pickerGap: CGFloat = 6

    init(store: NightThreadStore, canReact: Bool) {
        _store = ObservedObject(wrappedValue: store)
        self.canReact = canReact
    }

    private var pickerOpen: Bool { focus.openKey == store.key }

    var body: some View {
        let counts = store.summary.counts
        let layout = ReactionBarLayout.visible(counts: counts, mine: store.myReaction)
        // Just two reactions, so when you can react both are always there to tap:
        // no picker to find them in.
        let shown = canReact ? Reaction.allCases : layout.shown
        HStack(spacing: 0) {
            ForEach(shown) { reaction in
                pill(reaction, count: counts[reaction] ?? 0)
                    .transition(pillTransition)
            }
            if canReact {
                EmptyView()
            } else if layout.hidden > 0 {
                moreChip(hidden: layout.hidden)
            } else if layout.shown.isEmpty {
                Text("No reactions yet")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: Self.hitHeight)
            }
        }
        .fixedSize()
        .animation(changeAnimation, value: counts)
        .animation(changeAnimation, value: store.myReaction)
        .coordinateSpace(NamedCoordinateSpace.named(Self.space))
        .overlay(alignment: .bottomLeading) {
            if pickerOpen && canReact {
                ReactionPicker(selected: store.myReaction, hovered: hovered) { reaction in
                    pick(reaction)
                }
                // Bottom of the picker sits `pickerGap` above the pills' visible top.
                .offset(y: -(Self.hitHeight - Self.visibleTop + Self.pickerGap))
                .transition(pickerTransition)
            }
        }
        .onChange(of: canReact) { _, can in
            if !can { closePicker() }
        }
        .onDisappear { closePicker() }
    }

    /// The pills' visible top, measured down from the bar's top.
    private static var visibleTop: CGFloat { (hitHeight - pillHeight) / 2 }

    // MARK: Pieces

    private func pill(_ reaction: Reaction, count: Int) -> some View {
        let mine = store.myReaction == reaction
        return HStack(spacing: 4) {
            Text(reaction.emoji)
                .font(.system(size: 15))
                .scaleEffect(popping == reaction ? 1.35 : 1)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(mine ? AppColors.accent : AppColors.text)
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 9)
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
        // 44 pt tall hit target; the visible capsule stays 32 pt.
        .padding(.horizontal, Self.pillHitInset)
        .frame(height: Self.hitHeight)
        .contentShape(Rectangle())
        .onTapGesture { if canReact { react(reaction) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reaction.spokenName), \(count)")
        .accessibilityValue(mine ? "Your reaction" : "")
        .accessibilityAddTraits(canReact ? .isButton : [])
        .accessibilityAction {
            if canReact { react(reaction) }
        }
    }

    /// "+" or, with reactions hidden, "+N"; either way it opens the picker.
    private func plusButton(hidden: Int) -> some View {
        let showsMore = hidden > 0 && !pickerOpen
        return ZStack {
            if showsMore {
                Text("+\(hidden)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText(value: Double(hidden)))
                    .transition(.opacity)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .rotationEffect(.degrees(pickerOpen ? 45 : 0))
                    .transition(.opacity)
            }
        }
        .foregroundStyle(pickerOpen ? AppColors.accent : AppColors.textSecondary)
        .padding(.horizontal, showsMore ? 9 : 0)
        .frame(minWidth: Self.pillHeight, minHeight: Self.pillHeight, maxHeight: Self.pillHeight)
        .background {
            Capsule().fill(pickerOpen ? AppColors.accentDim : Color.white.opacity(0.06))
        }
        .overlay {
            Capsule().stroke(pickerOpen ? AppColors.accent.opacity(0.6) : AppColors.border, lineWidth: 1)
        }
        // 44 × 44 hit target at least.
        .frame(minWidth: Self.hitHeight, minHeight: Self.hitHeight)
        .contentShape(Rectangle())
        .animation(changeAnimation, value: pickerOpen)
        .animation(changeAnimation, value: hidden)
        .gesture(fanGesture { togglePicker() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pickerOpen ? "Close reactions" : "Add reaction")
        .accessibilityValue(hidden > 0 ? "\(hidden) more reactions" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { togglePicker() }
    }

    /// My own night: how many reactions don't fit, not tappable.
    private func moreChip(hidden: Int) -> some View {
        Text("+\(hidden)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(AppColors.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText(value: Double(hidden)))
            .padding(.horizontal, 9)
            .frame(height: Self.pillHeight)
            .background { Capsule().fill(Color.white.opacity(0.06)) }
            .overlay { Capsule().stroke(AppColors.border, lineWidth: 1) }
            .padding(.horizontal, Self.pillHitInset)
            .frame(height: Self.hitHeight)
            .accessibilityLabel("\(hidden) more reactions")
    }

    // MARK: Gestures

    /// Long-press opens the fan and tracks the finger; releasing on an emoji reacts,
    /// releasing anywhere else leaves the fan open to tap. A quick tap runs `onTap`.
    /// `hovered` is gesture state, so a cancelled drag can't leave an emoji raised.
    private func fanGesture(onTap: @escaping () -> Void) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0,
                                           coordinateSpace: NamedCoordinateSpace.named(Self.space)))
            .updating($hovered) { value, state, _ in
                guard case .second(true, let drag) = value, let drag else { return }
                let next = Self.reaction(at: drag.location)
                if next != state {
                    if next != nil { Haptics.shared.play(.selection) }
                    state = next
                }
            }
            .onChanged { value in
                guard case .second(true, _) = value else { return }
                if !pickerOpen { openPicker() }
            }
            .onEnded { value in
                guard case .second(true, let drag) = value,
                      let drag,
                      let reaction = Self.reaction(at: drag.location)
                else { return }
                pick(reaction)
            }
            .exclusively(before: TapGesture().onEnded { onTap() })
    }

    /// The emoji under a point in the bar's space. The picker sits right above the
    /// pills, starting at the bar's leading edge; only a finger that has moved up off
    /// the pills counts, so a long-press that is simply let go never reacts by accident.
    private static func reaction(at point: CGPoint) -> Reaction? {
        let pickerBottom = visibleTop - pickerGap
        guard point.y < visibleTop - 2,
              point.y > pickerBottom - ReactionPickerMetrics.height - 70,
              let index = ReactionPickerMetrics.index(atX: point.x)
        else { return nil }
        return Reaction.allCases[index]
    }

    // MARK: Actions

    private func togglePicker() {
        if pickerOpen { closePicker() } else { openPicker() }
    }

    private func openPicker() {
        guard canReact, !pickerOpen else { return }
        Haptics.shared.play(.light)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.72)) {
            focus.open(store.key)
        }
    }

    private func closePicker() {
        guard pickerOpen else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.28, dampingFraction: 0.85)) {
            focus.close(store.key)
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
