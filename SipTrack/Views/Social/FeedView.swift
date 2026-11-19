import SwiftUI

/// Small formatters shared by the feed and the friend night screen.
enum FriendNightFormat {
    static func bac(_ value: Double) -> String {
        String(format: "%.3f", max(0, value))
    }

    /// "42m" or "3h 12m".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    /// "just now", "12m ago", "3h ago".
    static func ago(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    static func drinkLabel(_ count: Int) -> String {
        count == 1 ? "1 drink" : "\(count) drinks"
    }

    /// Same icon keys as DrinkType; reuse its SF Symbol mapping.
    static func symbol(forIcon icon: String) -> String {
        DrinkType(
            id: "", name: "", defaultVolumeMl: 0, defaultAbv: 0, caloriesPerServing: 0,
            isPreset: false, icon: icon, colorHex: nil
        ).sfSymbol
    }
}

/// Small green dot that breathes while a night is live: it swells and dims while a
/// soft ring spreads out of it. Static under Reduce Motion.
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .stroke(AppColors.success.opacity(pulsing ? 0 : 0.6), lineWidth: 1)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulsing ? 2.4 : 1)
            }
            Circle()
                .fill(AppColors.success)
                .frame(width: 8, height: 8)
                .scaleEffect(reduceMotion ? 1 : (pulsing ? 0.85 : 1))
                .opacity(reduceMotion ? 1 : (pulsing ? 0.45 : 1))
        }
        .frame(width: 8, height: 8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// My own night on top ("You"), then friends' live nights and the last 24 hours of
/// finished ones, each as a post card.
struct FeedView: View {
    @EnvironmentObject var friends: FriendsStore
    /// Opens the same search destination as the toolbar magnifier.
    let onAddFriend: () -> Void

    /// The night whose comment sheet is up.
    @State private var thread: NightKey?
    /// The night pushed by tapping a card's body.
    @State private var openedNight: FeedItem?
    /// Any open reaction picker; closed by a scroll or a tap elsewhere in the feed.
    @ObservedObject private var pickerFocus = ReactionPickerFocus.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onAddFriend: @escaping () -> Void) {
        self.onAddFriend = onAddFriend
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let sections = FeedOrdering.sections(friends.feed, now: now)
            let mine = friends.myNight.flatMap { $0.night.expiresAt > now ? $0 : nil }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let mine {
                        card(mine, now: now, isMine: true)
                    }
                    if friends.friends.isEmpty {
                        emptyFriends
                    } else if sections.live.isEmpty && sections.recent.isEmpty {
                        Text("No nights from your friends in the last 24 hours.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        if !sections.live.isEmpty {
                            header("Live now")
                            ForEach(sections.live) { item in
                                card(item, now: now, isMine: false)
                            }
                        }
                        if !sections.recent.isEmpty {
                            header("Last 24 hours")
                            ForEach(sections.recent) { item in
                                card(item, now: now, isMine: false)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // Only while a picker is open, so normal taps are untouched. Buttons and the
                // reaction gestures inside the cards take precedence over this one.
                .gesture(
                    TapGesture().onEnded { ReactionPickerFocus.dismiss(reduceMotion: reduceMotion) },
                    including: pickerFocus.isOpen ? .all : .subviews
                )
            }
            .onScrollPhaseChange { _, phase in
                if phase.isScrolling { ReactionPickerFocus.dismiss(reduceMotion: reduceMotion) }
            }
        }
        .navigationDestination(isPresented: openedNightBinding) {
            if let openedNight {
                FriendNightView(item: openedNight)
            }
        }
        .sheet(item: $thread) { key in
            ThreadSheetPlaceholder(key: key)
        }
    }

    private func card(_ item: FeedItem, now: Date, isMine: Bool) -> some View {
        FeedPostCard(
            item: item,
            now: now,
            isMine: isMine,
            onOpenThread: { thread = NightKey(owner: item.profile.uid, night: item.night) },
            onOpenNight: { openedNight = item }
        )
    }

    private var openedNightBinding: Binding<Bool> {
        Binding(
            get: { openedNight != nil },
            set: { if !$0 { openedNight = nil } }
        )
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private var emptyFriends: some View {
        VStack {
            Button(action: onAddFriend) {
                Text("Add a friend")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(AppColors.accent, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// Stand-in for the comment sheet until it lands.
private struct ThreadSheetPlaceholder: View {
    let key: NightKey

    init(key: NightKey) {
        self.key = key
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(AppColors.accent)
            Text("Comments")
                .font(.headline)
                .foregroundStyle(AppColors.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
