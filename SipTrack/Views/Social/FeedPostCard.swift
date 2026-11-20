import SwiftUI

/// One shared night in the feed, as a post: who and how long, BAC, a mini curve that
/// draws itself in, drink chips that cascade in, the last drink, reactions, the
/// comment count and the latest comment. Tapping the body opens the full night;
/// 💬 and the latest comment open the thread.
struct FeedPostCard: View {
    let item: FeedItem
    let now: Date
    /// My own night: labelled "You", no reacting.
    let isMine: Bool
    let onOpenThread: () -> Void
    let onOpenNight: () -> Void

    @EnvironmentObject private var friends: FriendsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var store: NightThreadStore

    private static let radius: CGFloat = 20
    private static let maxChips = 3

    init(item: FeedItem, now: Date, isMine: Bool,
         onOpenThread: @escaping () -> Void, onOpenNight: @escaping () -> Void) {
        self.item = item
        self.now = now
        self.isMine = isMine
        self.onOpenThread = onOpenThread
        self.onOpenNight = onOpenNight
        // Shared with the comment sheet through the store cache.
        let key = NightKey(owner: item.profile.uid, night: item.night)
        let myUid = FirebaseManager.shared.currentUserId() ?? ""
        _store = ObservedObject(wrappedValue: NightThreadStore.store(for: key, myUid: myUid))
    }

    var body: some View {
        let night = item.night
        let live = night.isLive(now: now)
        let bac = live ? night.bac(at: now) : night.peakBAC
        let stageColor = IntoxicationStage.stage(for: bac).color
        let latest = latestVisibleComment

        VStack(alignment: .leading, spacing: 12) {
            Button(action: openNight) {
                VStack(alignment: .leading, spacing: 12) {
                    header(live: live, bac: bac, color: stageColor)
                    MiniBACCurve(
                        data: NightBACChartData(shared: night, now: now),
                        live: live,
                        color: IntoxicationStage.stage(for: night.peakBAC).color
                    )
                    chipsRow
                    lastDrinkLine
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(live: live, bac: bac))
            .accessibilityHint("Opens the night")
            .accessibilityAddTraits(.isButton)

            footer
                // 44 pt hit targets inside, 32 pt visuals: keep the visual rhythm.
                .padding(.vertical, -6)
                .zIndex(1)

            if let latest {
                latestCommentRow(latest)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3), value: latest?.id)
        .padding(14)
        .premiumCard(
            radius: Self.radius,
            tint: AppColors.success,
            tintOpacity: live ? 0.035 : 0
        )
        .overlay {
            if live {
                RoundedRectangle(cornerRadius: Self.radius)
                    .stroke(AppColors.success.opacity(0.45), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: startStore)
        // The same card can be handed a new night (the friend started another while
        // it is on screen): the new night's store has to start too.
        .onChange(of: store.key) { _, _ in startStore() }
    }

    private func startStore() {
        if let me = friends.myProfile?.username, !me.isEmpty { store.myUsername = me }
        store.start()
    }

    // MARK: - Taps

    /// With a reaction picker open anywhere, a tap on the card only closes it.
    private func openNight() {
        if ReactionPickerFocus.shared.isOpen {
            ReactionPickerFocus.dismiss(reduceMotion: reduceMotion)
        } else {
            onOpenNight()
        }
    }

    private func openThread() {
        ReactionPickerFocus.dismiss(reduceMotion: reduceMotion)
        onOpenThread()
    }

    // MARK: - Header

    private func header(live: Bool, bac: Double, color: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            AvatarView(profile: item.profile, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(isMine ? "You" : "@\(item.profile.username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if live { LiveDot() }
                    Text(statusText(live: live))
                        .font(.caption)
                        .foregroundStyle(live ? AppColors.success : AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(FriendNightFormat.bac(bac))
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: bac))
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.8),
                               value: bac)
                Text(live ? "BAC now" : "peak")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    /// "Live · 2h 10m" or "Ended 5h ago · 4h 30m".
    private func statusText(live: Bool) -> String {
        let night = item.night
        if live {
            return "Live · \(FriendNightFormat.duration(now.timeIntervalSince(night.startedAt)))"
        }
        let ended = night.endedAt ?? night.lastDrinkAt
        let ago = FriendNightFormat.ago(now.timeIntervalSince(ended))
        let length = FriendNightFormat.duration(ended.timeIntervalSince(night.startedAt))
        return ago == "just now" ? "Ended just now · \(length)" : "Ended \(ago) · \(length)"
    }

    // MARK: - Drinks

    private var chips: [DrinkChip.Model] {
        DrinkSummary.chips(item.night.drinks).map {
            DrinkChip.Model(name: $0.name, icon: $0.icon, count: $0.count)
        }
    }

    @ViewBuilder private var chipsRow: some View {
        let all = chips
        if !all.isEmpty {
            let visible = Array(all.prefix(Self.maxChips))
            let hidden = all.count - visible.count
            HStack(spacing: 6) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, chip in
                    DrinkChip(model: chip, index: index)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }
                if hidden > 0 {
                    DrinkChip(model: DrinkChip.Model(name: "+\(hidden)", icon: nil, count: 1),
                              index: visible.count)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.7),
                       value: all)
        }
    }

    @ViewBuilder private var lastDrinkLine: some View {
        if let last = item.night.drinks.max(by: { $0.at < $1.at }) {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                Text("Last: \(last.name) · \(FriendNightFormat.ago(now.timeIntervalSince(last.at)))")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let count = store.summary.commentCount
        return HStack(alignment: .center, spacing: 8) {
            ReactionBar(store: store, canReact: true)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Button(action: openThread) {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14, weight: .semibold))
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText(value: Double(count)))
                    }
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background { Capsule().fill(Color.white.opacity(0.06)) }
                .overlay { Capsule().stroke(AppColors.border, lineWidth: 1) }
                .fixedSize()
                // 44 × 44 hit target at least around the 32 pt capsule.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.7),
                           value: count)
            }
            .buttonStyle(CardPressStyle())
            .accessibilityLabel(count == 1 ? "1 comment" : "\(count) comments")
            .accessibilityHint("Opens the comments")
        }
    }

    // MARK: - Latest comment

    /// The newest comment from someone I haven't blocked.
    private var latestVisibleComment: ThreadComment? {
        let blocked = Set(friends.blocked.map(\.uid))
        return store.summary.latest.last { !blocked.contains($0.uid) }
    }

    private func latestCommentRow(_ comment: ThreadComment) -> some View {
        Button(action: openThread) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(commentText(comment))
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
                Text(FriendNightFormat.ago(now.timeIntervalSince(comment.at)))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel("Latest comment, @\(comment.username): \(comment.text)")
        .accessibilityHint("Opens the comments")
    }

    /// "@beto " in bold, then the text with mentioned names in the accent colour.
    private func commentText(_ comment: ThreadComment) -> AttributedString {
        var result = AttributedString("@\(comment.username) ")
        result.font = Font.footnote.weight(.semibold)
        result.foregroundColor = AppColors.text
        for (text, isMention) in MentionText.segments(comment.text, mentions: comment.mentions) {
            var part = AttributedString(text)
            part.foregroundColor = isMention ? AppColors.accent : AppColors.textSecondary
            if isMention { part.font = Font.footnote.weight(.semibold) }
            result += part
        }
        return result
    }

    // MARK: - Accessibility

    private func accessibilityText(live: Bool, bac: Double) -> String {
        let night = item.night
        let who = isMine ? "Your night" : "@\(item.profile.username)"
        let value = FriendNightFormat.bac(bac)
        let drinks = FriendNightFormat.drinkLabel(night.drinkCount)
        if live {
            return "\(who), live, BAC \(value), \(drinks), \(FriendNightFormat.duration(now.timeIntervalSince(night.startedAt)))"
        }
        let ended = night.endedAt ?? night.lastDrinkAt
        return "\(who), peak \(value), \(drinks), ended \(FriendNightFormat.ago(now.timeIntervalSince(ended)))"
    }
}

// MARK: - Drink chip

/// "🍺 Beer ×3". Pops in on arrival, 40 ms after the one before it.
private struct DrinkChip: View {
    struct Model: Identifiable, Equatable {
        var name: String
        /// nil for the "+2" overflow chip.
        var icon: String?
        var count: Int
        var id: String { name }
    }

    let model: Model
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    init(model: Model, index: Int) {
        self.model = model
        self.index = index
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon = model.icon {
                Image(systemName: FriendNightFormat.symbol(forIcon: icon))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            }
            Text(model.icon == nil || model.count == 1 ? model.name : "\(model.name) ×\(model.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background { Capsule().fill(AppColors.accentDim.opacity(0.6)) }
        .overlay { Capsule().stroke(AppColors.accent.opacity(0.18), lineWidth: 1) }
        .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) { appeared = true }
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.65).delay(0.3 + Double(index) * 0.04)) {
                    appeared = true
                }
            }
        }
    }
}

// MARK: - Mini curve

/// The night's BAC in 44 pt. Draws left to right on arrival (trim 0 → 1); a live
/// night continues as a dashed projection. Under Reduce Motion it is simply there.
private struct MiniBACCurve: View {
    let data: NightBACChartData
    let live: Bool
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var projected: CGFloat = 0
    @State private var dotShown = false

    init(data: NightBACChartData, live: Bool, color: Color) {
        self.data = data
        self.live = live
        self.color = color
    }

    var body: some View {
        let history = unitPoints(data.history)
        // A finished night is one solid line; a live one splits at now.
        let solid: [CGPoint] = live ? history : history + Array(unitPoints(data.projection).dropFirst())
        let projection: [CGPoint] = live ? unitPoints(data.projection) : []

        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: 3, dy: 3)
            ZStack {
                CurveShape(points: solid, closed: true)
                    .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(Double(drawn))
                CurveShape(points: solid, closed: false)
                    .trim(from: 0, to: drawn)
                    .stroke(
                        LinearGradient(colors: [AppColors.accent.opacity(0.85), color],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                if projection.count > 1 {
                    CurveShape(points: projection, closed: false)
                        .trim(from: 0, to: projected)
                        .stroke(color.opacity(0.6),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
                }
                if live, let end = history.last {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .shadow(color: color.opacity(0.9), radius: 4)
                        .scaleEffect(dotShown ? 1 : 0.1)
                        .opacity(dotShown ? 1 : 0)
                        .position(CurveShape.place(end, in: rect))
                }
            }
        }
        .frame(height: 44)
        .onAppear(perform: draw)
        .accessibilityHidden(true)
    }

    private func draw() {
        guard drawn == 0 else { return }
        if reduceMotion {
            drawn = 1
            projected = 1
            dotShown = true
            return
        }
        withAnimation(.easeOut(duration: 0.9)) { drawn = 1 }
        withAnimation(.easeOut(duration: 0.5).delay(0.8)) { projected = 1 }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.8)) { dotShown = true }
    }

    /// x by time across the chart's span, y by BAC against its ceiling, both 0...1.
    private func unitPoints(_ points: [BACDataPoint]) -> [CGPoint] {
        let span = max(1, data.end.timeIntervalSince(data.start))
        let top = max(data.yMax, 0.0001)
        return points.map { point in
            CGPoint(
                x: min(max(point.date.timeIntervalSince(data.start) / span, 0), 1),
                y: min(max(point.bac / top, 0), 1)
            )
        }
    }
}

/// A polyline through unit points; `closed` drops it to the baseline for the fill.
private struct CurveShape: Shape {
    var points: [CGPoint]
    var closed: Bool

    nonisolated static func place(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.maxY - point.y * rect.height)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        let inset = rect.insetBy(dx: 3, dy: 3)
        path.move(to: Self.place(first, in: inset))
        for point in points.dropFirst() {
            path.addLine(to: Self.place(point, in: inset))
        }
        if closed, let last = points.last {
            path.addLine(to: CGPoint(x: Self.place(last, in: inset).x, y: rect.maxY))
            path.addLine(to: CGPoint(x: Self.place(first, in: inset).x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// A light press: dims and settles a touch. No scale under Reduce Motion.
private struct CardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
