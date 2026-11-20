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

// MARK: - Bar

/// When I can react: both reactions as pills, mine highlighted; tap one to react
/// with it (tap mine to take it back). On my own night: the most used reactions with
/// their counts, and "+N" when more are hidden.
struct ReactionBar: View {
    @ObservedObject private var store: NightThreadStore
    let canReact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popping: Reaction?
    @State private var burst: Reaction?
    @State private var burstID = 0

    /// What you see.
    private static let pillHeight: CGFloat = 32
    /// What you can tap.
    private static let hitHeight: CGFloat = 44
    /// Horizontal hit padding around each pill; two neighbours make the 6 pt gap.
    private static let pillHitInset: CGFloat = 3

    init(store: NightThreadStore, canReact: Bool) {
        _store = ObservedObject(wrappedValue: store)
        self.canReact = canReact
    }

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
    }

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

    // MARK: Actions

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
