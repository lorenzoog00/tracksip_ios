import SwiftUI

/// Someone's profile: their big photo, name and @username, then for a friend the stats
/// card and their night (live, or the last 24 hours) as the feed shows it. Anyone else
/// gets the Add / Requested / Accept button and a locked card instead, since stats and
/// nights are friends-only. Opened from a feed card's avatar or name, My Friends and
/// Find friends. Reads `public_profiles/{uid}` (and, for a friend, `profile_stats/{uid}`)
/// once when opened, again on pull to refresh, and the stats again on becoming friends.
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
    /// A stats read has finished since you last became friends (or opened this as one).
    @State private var statsLoaded = false
    /// The stats read failed (offline, say) and none were read before. A denied read
    /// isn't a failure: it means no stats to show.
    @State private var statsFailed = false
    /// The night pushed by tapping a card.
    @State private var openedNight: FeedItem?
    /// The night whose comment sheet is up.
    @State private var thread: NightKey?

    /// Why Find friends suggested them, for the mutual-friends line; nil when opened
    /// from anywhere else.
    private let suggestion: PersonSuggestion.Reason?

    private static let photoSize: CGFloat = 200

    init(profile: FriendProfile, suggestion: PersonSuggestion.Reason? = nil) {
        _profile = State(initialValue: profile)
        self.suggestion = suggestion
    }

    /// From the friends listener, so a request accepted while this is open (here or on
    /// their phone) switches to the friend layout once the friendship is in.
    private var isFriend: Bool {
        friends.friends.contains { $0.uid == profile.uid }
    }

    private var layout: Layout {
        Layout.for(isFriend: isFriend, stats: stats)
    }

    /// Accepted (or made friends by a request), and the friends list hasn't caught up
    /// yet: the stats come next, so no "Add" card meanwhile.
    private var awaitingFriendList: Bool {
        !isFriend && friends.rowState(for: profile.uid) == .friend
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                switch layout {
                case .friendStats, .friendNoStats:
                    statsSection
                    nightSection
                case .locked:
                    relationshipSection
                    if awaitingFriendList {
                        loadingStatsRow
                    } else {
                        lockedCard
                    }
                }
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
        // Just became friends: their stats can be read now, so read them.
        .onChange(of: isFriend) { _, nowFriend in
            guard nowFriend else { return }
            statsLoaded = false
            Task { await load() }
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

    /// Reads their profile card and, for a friend, their stats side by side. A failed
    /// profile read keeps the one shown; a failed stats read keeps the last stats read.
    private func load() async {
        let uid = profile.uid
        let readsStats = isFriend
        async let freshProfile = Self.readProfile(uid: uid)
        async let freshStats = Self.readStats(uid: uid, isFriend: readsStats)
        let (newProfile, statsRead) = await (freshProfile, freshStats)

        if let newProfile, newProfile != profile { profile = newProfile }
        if let statsRead {
            switch statsRead {
            case .success(let value):
                stats = value
                statsFailed = false
            case .failure:
                statsFailed = stats == nil
            }
        }
        if !loaded || (statsRead != nil && !statsLoaded) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.8)) {
                loaded = true
                if statsRead != nil { statsLoaded = true }
            }
        }
    }

    private static func readProfile(uid: String) async -> FriendProfile? {
        try? await FirebaseManager.shared.fetchPublicProfile(uid: uid)
    }

    /// Nil, with no read, for anyone but a friend: the rules let only friends read
    /// stats. Success with nil: no doc, or not allowed to read it (not friends any more).
    private static func readStats(uid: String, isFriend: Bool) async -> Result<ProfileStats?, Error>? {
        guard isFriend else { return nil }
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

    /// A spinner until the stats read is back, then the card fades and scales in.
    private var statsSection: some View {
        ZStack {
            if statsLoaded {
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
            if let stats, layout == .friendStats {
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
                    .foregroundStyle(AppColors.textSecondary)
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

    // MARK: - Layout

    /// What the screen shows under the header.
    nonisolated enum Layout: Equatable {
        /// A friend with nights counted: the filled stats card and their night.
        case friendStats
        /// A friend with no stats doc, or one that counts no nights: "No stats yet"
        /// (or the read failed) and their night.
        case friendNoStats
        /// Anyone else, a request either way included: the relationship button and
        /// the locked card. Stats are never read for them.
        case locked

        nonisolated static func `for`(isFriend: Bool, stats: ProfileStats?) -> Layout {
            guard isFriend else { return .locked }
            if let stats, stats.nights > 0 { return .friendStats }
            return .friendNoStats
        }
    }

    /// The suggested row's own words ("Friends with @ana and 2 others", "3 friends in
    /// common"); nil when they weren't suggested for mutual friends.
    static func mutualLine(_ reason: PersonSuggestion.Reason?) -> String? {
        guard let reason, case .mutualFriends(let count, _) = reason, count > 0 else { return nil }
        return reason.subtitle
    }

    // MARK: - Not friends

    /// Why Find friends suggested them, then the same Add / Requested / Accept the Find
    /// friends rows offer, flipping on the tap like them (`FriendsStore.pending`).
    private var relationshipSection: some View {
        VStack(spacing: 12) {
            if let mutual = Self.mutualLine(suggestion) {
                Text(mutual)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            relationshipControl
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var relationshipControl: some View {
        let state = friends.rowState(for: profile.uid)
        // Held from the tap until the listener shows the change, so no second tap.
        let inFlight = coordinator.isBusy(profile) || friends.pending.isPending(profile.uid)
        switch state {
        case .add:
            relationshipButton("Add friend", icon: "person.badge.plus",
                               failure: "Couldn't send request", disabled: inFlight) {
                try await friends.sendRequest(to: profile.uid)
            }
        case .accept:
            relationshipButton("Accept", icon: "person.crop.circle.badge.checkmark",
                               failure: "Couldn't accept request", disabled: inFlight) {
                try await friends.respond(to: profile.uid, accept: true)
            }
        case .pending:
            // A menu, so a stray tap doesn't take the request back.
            Menu {
                Button("Cancel request", role: .destructive) {
                    coordinator.run(profile, failure: "Couldn't cancel request") {
                        try await friends.cancelRequest(to: profile.uid)
                    }
                }
            } label: {
                relationshipLabel("Requested", icon: "clock", primary: false)
            }
            .disabled(inFlight)
            .accessibilityHint("Lets you cancel your request")
        case .friend:
            // Accepted here, until the friends listener has it and the layout switches.
            relationshipLabel("Friends", icon: "checkmark", primary: false)
        }
    }

    /// The store flips the state at once; a failure flips it back and the coordinator
    /// shows the error.
    private func relationshipButton(
        _ title: String,
        icon: String,
        failure: String,
        disabled: Bool,
        _ work: @escaping () async throws -> Void
    ) -> some View {
        Button {
            coordinator.run(profile, failure: failure, work)
        } label: {
            relationshipLabel(title, icon: icon, primary: true)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private func relationshipLabel(_ title: String, icon: String, primary: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(primary ? Color.black : AppColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(primary ? AppColors.accent : AppColors.border)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// In place of the stats card: only friends can see stats.
    private var lockedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text("Add @\(profile.username) to see their stats.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .premiumCard(radius: 20)
        .accessibilityElement(children: .combine)
    }

    /// In place of the locked card while `awaitingFriendList`.
    private var loadingStatsRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(AppColors.accent)
            Text("Loading stats…")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
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
