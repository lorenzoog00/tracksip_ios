import SwiftUI

/// A friend's profile: their big photo, name and @username, the stats card, then
/// their night (live, or the last 24 hours) as the feed shows it. Opened from a feed
/// card's avatar or name and from My Friends. Reads `public_profiles/{uid}` and
/// `profile_stats/{uid}` once when opened, and again on pull to refresh.
struct FriendProfileView: View {
    @EnvironmentObject private var friends: FriendsStore
    @StateObject private var coordinator = FriendActionCoordinator()
    /// Any open reaction picker; closed by a scroll or a tap elsewhere.
    @ObservedObject private var pickerFocus = ReactionPickerFocus.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    /// As opened, then as `public_profiles` last said.
    @State private var profile: FriendProfile
    @State private var stats: ProfileStats?
    /// The first read has finished, whatever it found.
    @State private var loaded = false
    /// The stats read failed (offline, say) and none were read before. A denied read
    /// isn't a failure: it means no stats to show.
    @State private var statsFailed = false
    /// The night pushed by tapping a card.
    @State private var openedNight: FeedItem?
    /// The night whose comment sheet is up.
    @State private var thread: NightKey?

    private static let photoSize: CGFloat = 200

    init(profile: FriendProfile) {
        _profile = State(initialValue: profile)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                statsSection
                nightSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            // Only while a reaction picker is open: a tap elsewhere closes it.
            .gesture(
                TapGesture().onEnded { ReactionPickerFocus.dismiss(reduceMotion: reduceMotion) },
                including: pickerFocus.isOpen ? .all : .subviews
            )
        }
        .onScrollPhaseChange { _, phase in
            if phase.isScrolling { ReactionPickerFocus.dismiss(reduceMotion: reduceMotion) }
        }
        .refreshable { await load() }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("@\(profile.username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ReportBlockMenu(profile: profile, coordinator: coordinator)
            }
        }
        .friendActionDialogs(coordinator)
        .navigationDestination(isPresented: openedNightBinding) {
            if let openedNight {
                FriendNightView(item: openedNight)
            }
        }
        .sheet(item: $thread) { key in
            NightThreadSheet(key: key, ownerName: profile.username)
        }
        // Once when opened: coming back from their night doesn't read again.
        .task {
            guard !loaded else { return }
            await load()
        }
        // Blocked from here: their profile doesn't stay on screen.
        .onChange(of: friends.blockedUidSet.contains(profile.uid)) { _, blocked in
            if blocked { dismiss() }
        }
    }

    private var openedNightBinding: Binding<Bool> {
        Binding(
            get: { openedNight != nil },
            set: { if !$0 { openedNight = nil } }
        )
    }

    // MARK: - Reading

    /// Reads their profile card and stats side by side. A failed profile read keeps the
    /// one shown; a failed stats read keeps the last stats read.
    private func load() async {
        let uid = profile.uid
        async let freshProfile = Self.readProfile(uid: uid)
        async let freshStats = Self.readStats(uid: uid)
        let (newProfile, statsRead) = await (freshProfile, freshStats)

        if let newProfile, newProfile != profile { profile = newProfile }
        switch statsRead {
        case .success(let value):
            stats = value
            statsFailed = false
        case .failure:
            statsFailed = stats == nil
        }
        if !loaded {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.8)) {
                loaded = true
            }
        }
    }

    private static func readProfile(uid: String) async -> FriendProfile? {
        try? await FirebaseManager.shared.fetchPublicProfile(uid: uid)
    }

    /// Success with nil: no doc, or not allowed to read it (not friends any more).
    private static func readStats(uid: String) async -> Result<ProfileStats?, Error> {
        do {
            return .success(try await FirebaseManager.shared.fetchProfileStats(uid: uid))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            AvatarView(profile: profile, size: Self.photoSize)
                .overlay { Circle().stroke(AppColors.rimLight, lineWidth: 1) }
                .shadow(color: AppColors.accentGlow.opacity(0.35), radius: 28, y: 8)
                .padding(.top, 12)
            VStack(spacing: 4) {
                if let name = profile.name {
                    Text(name)
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppColors.text)
                    Text("@\(profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    // No name: the @username is the title, so it always shows.
                    Text("@\(profile.username)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppColors.text)
                }
            }
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats

    /// A spinner until the first read is back, then the card fades and scales in.
    private var statsSection: some View {
        ZStack {
            if loaded {
                statsCard
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
            } else {
                ProgressView()
                    .tint(AppColors.accent)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .transition(.opacity)
            }
        }
    }

    private var statsCard: some View {
        Group {
            if let stats, stats.nights > 0 {
                filledCard(stats)
            } else {
                emptyCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .premiumCard(radius: 20)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: stats)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: statsFailed)
    }

    private func filledCard(_ stats: ProfileStats) -> some View {
        // No night in the last 90 days: no averages or favorite to show. avg_drinks is
        // 0 then, as a counted night has a drink; a parsed doc already reads it as nil.
        let inWindow = (stats.avgDrinks ?? 0) > 0
        let drinks = inWindow ? stats.avgDrinks : nil
        let waters = inWindow ? stats.avgWater : nil
        let favorite = inWindow ? stats.favoriteDrink : nil
        return VStack(alignment: .leading, spacing: 14) {
            statRow(icon: "moon.stars.fill", color: AppColors.accent,
                    value: stats.nights.formatted(),
                    label: stats.nights == 1 ? "night logged" : "nights logged")

            VStack(alignment: .leading, spacing: 10) {
                Text("Last 90 days")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(.uppercase)
                statRow(icon: "wineglass.fill", color: AppColors.accent,
                        value: Self.average(drinks), label: "drinks / night")
                statRow(icon: "drop.fill", color: AppColors.water,
                        value: Self.average(waters), label: "waters / night")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    icon("star.fill", color: AppColors.accentWarm)
                    Text("Favorite: \(Text(favorite ?? "—").fontWeight(.semibold).foregroundStyle(AppColors.text))")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                icon("calendar", color: AppColors.textSecondary)
                Text("On TrackSip since \(stats.memberSince.formatted(.dateTime.month(.wide).year()))")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "No stats yet" when there's no doc, it can't be read (not friends) or it counts
    /// no nights; a short note to pull again when the read itself failed.
    private var emptyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: statsFailed ? "wifi.exclamationmark" : "chart.bar.xaxis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(statsFailed ? "Couldn't load stats" : "No stats yet")
                    .font(.headline)
                    .foregroundStyle(AppColors.text)
                if statsFailed {
                    Text("Pull down to try again.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func statRow(icon name: String, color: Color, value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            icon(name, color: color)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppColors.text)
                .contentTransition(.numericText())
            Text(label)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func icon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 24)
            .accessibilityHidden(true)
    }

    /// "3.4", or "2" for 2.0; "—" with none.
    private static func average(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    // MARK: - Their night

    /// Their nights on the feed (live first, then the last 24 hours), as the same cards,
    /// opening the full night and the comments as the feed does.
    private var nightSection: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let sections = FeedOrdering.sections(
                friends.feed.filter { $0.profile.uid == profile.uid }, now: now
            )
            VStack(alignment: .leading, spacing: 14) {
                if !sections.live.isEmpty {
                    sectionHeader("Live now")
                    ForEach(sections.live) { item in
                        card(item, now: now)
                    }
                }
                if !sections.recent.isEmpty || sections.live.isEmpty {
                    sectionHeader("Last 24 hours")
                }
                ForEach(sections.recent) { item in
                    card(item, now: now)
                }
                if sections.live.isEmpty && sections.recent.isEmpty {
                    Text("No nights in the last 24 hours.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// No profile button on these cards: this is the profile.
    private func card(_ item: FeedItem, now: Date) -> some View {
        FeedPostCard(
            item: item,
            now: now,
            isMine: false,
            onOpenThread: { thread = item.key },
            onOpenNight: { openedNight = item }
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}
