import SwiftUI
import Charts
import UIKit
import Photos

struct SummaryView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @State private var notes = ""
    @State private var notesSavedAt: Date? = nil
    @State private var showDeleteConfirm = false
    @State private var showPDFShare = false
    @State private var pdfURL: URL? = nil
    @State private var chartSelection: Date?
    @State private var relatedChartTime: Date?
    @State private var storyCreated = false
    @State private var storyHasMedia: Bool?
    @State private var storyPhotoCount = 0
    @State private var storyPreviews: [StoryAsset] = []
    @State private var savedStoryVideo: URL?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var event: NightEvent?      { appState.events.first { $0.id == eventId } }

    var body: some View {
        guard let event = event else {
            return AnyView(Text("Event not found").foregroundStyle(AppColors.textSecondary))
        }
        return AnyView(content(event: event))
    }

    private func content(event: NightEvent) -> some View {
        let review = appState.nightReview(for: event)
        let drinkCount = review.drinkCount
        let calories = review.calories
        let standardDrinks = review.standardDrinks
        let peakBAC = review.peak?.bac ?? 0
        let timeline = review.timeline

        return ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 5) {
                        Text(event.displayName)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(AppColors.text)
                        Text(eventDateRange(event))
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(durationString(event.duration))
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                        if drinkCount > 0 {
                            Text(String(format: "%d drinks logged · %.1f standard drinks", drinkCount, standardDrinks))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .padding(.top)

                    if !timeline.isEmpty {
                        NightBACChartCard(
                            data: NightBACChartData(
                                eventStart: event.startTime, now: review.end, currentBAC: review.bac(at: review.end),
                                samples: timeline, entries: review.entries, drinkTypes: appState.allDrinkTypes,
                                isFinished: event.endTime != nil
                            ),
                            externalSelection: Binding(
                                get: { chartSelection },
                                set: {
                                    chartSelection = $0
                                    relatedChartTime = nil
                                }
                            ),
                            relatedTime: relatedChartTime
                        )
                        .padding(.horizontal)
                        .id("summary-chart")
                    }

                    if event.endTime != nil, drinkCount > 0 || storyHasMedia != false || savedStoryVideo != nil {
                        SummaryStoryCard(eventId: eventId, created: storyCreated, photoCount: storyPhotoCount,
                                         previews: storyPreviews, savedVideo: savedStoryVideo)
                        .padding(.horizontal)
                    }

                    if !review.highlights.isEmpty {
                        SummaryHighlightsCard(highlights: review.highlights) { highlight in
                            Haptics.shared.play(.selection)
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.34)) {
                                chartSelection = highlight.time
                                relatedChartTime = highlight.relatedTime
                                scroll.scrollTo("summary-chart", anchor: .top)
                            }
                        }
                        .padding(.horizontal)
                    }

                    if let comparison = review.comparison {
                        SummaryComparisonCard(comparison: comparison)
                            .padding(.horizontal)
                    }

                    if calories > 0 {
                        CalorieEquivalenciesCard(calories: calories)
                    }

                    SummaryLogCard(review: review, drinkTypes: appState.allDrinkTypes)
                        .padding(.horizontal)

                    DisclosureGroup {
                        NightAnalysisCard(eventId: eventId)
                            .padding(.top, 8)
                    } label: {
                        Label("Night analysis", systemImage: "sparkles").font(.headline)
                    }
                    .padding(16)
                    .premiumCard(radius: 14)
                    .padding(.horizontal)

                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Notes", systemImage: "note.text")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            if notesSavedAt != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                    Text("Saved")
                                        .font(.system(size: 14))
                                }
                                .foregroundStyle(AppColors.success)
                            }
                        }
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(AppColors.surface)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                            .foregroundStyle(AppColors.text)
                            .onChange(of: notes) { _, newVal in
                                appState.updateEventNotes(id: eventId, notes: newVal)
                                notesSavedAt = Date()
                            }
                    }
                    .padding(.horizontal)

                    // Delete
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text("Delete Night")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(AppColors.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.dangerDim)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(AppColors.background)
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    // Share card (image)
                    Button {
                        let meanBAC = event.endTime.map {
                            BACCalculator.meanBACForEvent(
                                entries: review.entries, drinkTypes: appState.allDrinkTypes, profile: appState.userProfile,
                                eventStart: event.startTime, eventEnd: $0, stomachState: event.stomachState ?? .empty,
                                stomachStateTimestamp: event.stomachStateTimestamp, foodEntries: review.foods
                            )
                        } ?? 0
                        let card = SummaryShareCard(
                            event: event,
                            meanBAC: meanBAC,
                            drinkCount: drinkCount,
                            standardDrinks: standardDrinks,
                            timeline: timeline,
                            calories: calories,
                            waterCount: review.waters.count
                        ).environment(\.colorScheme, .dark)
                        let renderer = ImageRenderer(content: card)
                        renderer.proposedSize = .init(width: 390, height: 693)
                        renderer.scale = 3.0
                        guard let image = renderer.uiImage else { return }
                        let av = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                        // Sharing used to present on the first window's root,
                        // so with anything already on screen the button did
                        // nothing at all and said nothing about it.
                        if let anchor = PresentationAnchor.topMost() {
                            av.popoverPresentationController?.sourceView = anchor.view
                            anchor.present(av, animated: true)
                        }
                    } label: {
                        Label("Share Night Card", systemImage: "square.and.arrow.up")
                    }

                    // Export PDF (Pro + report required)
                    if appState.isPro, let report = event.aiReport {
                        Button {
                            let reportData = NightReportData(
                                event: event,
                                report: report,
                                drinkCount: drinkCount,
                                peakBAC: peakBAC,
                                calories: calories,
                                waterCount: review.waters.count,
                                standardDrinks: standardDrinks,
                                userProfile: appState.userProfile
                            )
                            if let url = exportNightReportPDF(reportData) {
                                pdfURL = url
                                showPDFShare = true
                            }
                        } label: {
                            Label("Export Health Report (PDF)", systemImage: "doc.text.fill")
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppColors.accent)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    appState.updateEventNotes(id: eventId, notes: notes)
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
            }
        }
        .sheet(isPresented: $showPDFShare) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
        .onAppear {
            notes = event.notes ?? ""
            refreshStoryPreview(for: event)
            // Show interstitial when browsing past summaries (not triggered by endEvent which already fires one).
            // Uses the alternating method so it only fires every other visit.
            if appState.pendingSummaryEventId != eventId {
                AdManager.shared.showInterstitialForBrowse(isPro: appState.isPro)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStoryPreview(for: event) }
        }
        .onChange(of: showDeleteConfirm) { _, asked in
            guard asked else { return }
            showDeleteConfirm = false
            NoticeCenter.shared.show(Notice(
                icon: "trash.fill",
                tone: .danger,
                title: "Delete this night?",
                message: "Every drink, water and snack logged that night goes with it. This can't be undone.",
                actions: [
                    NoticeAction("Delete", kind: .destructive) {
                        appState.deleteEvent(eventId)
                        dismiss()
                    },
                    NoticeAction("Cancel", kind: .quiet)
                ]
            ))
        }
    }

    private func refreshStoryPreview(for event: NightEvent) {
        guard let end = event.endTime else { return }
        let state = DataStore.shared.loadNightStoryState(eventId: event.id)
        storyCreated = state.generatedAt != nil
        savedStoryVideo = DataStore.shared.savedNightStoryVideo(eventId: event.id)
        let assets = PhotoLibraryService.assets(from: event.startTime, to: end)
        storyHasMedia = PhotoLibraryService.status == .notDetermined ? nil : !assets.isEmpty
        let selected = assets.filter { !state.excludedAssetIds.contains($0.id) }
        storyPhotoCount = selected.count
        if selected.count > 3, let first = selected.first, let last = selected.last {
            storyPreviews = [first, selected[selected.count / 2], last]
        } else {
            storyPreviews = selected
        }
    }

    private func eventDateRange(_ event: NightEvent) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let start = f.string(from: event.startTime)
        if let end = event.endTime {
            f.dateStyle = .none
            return "\(start) – \(f.string(from: end))"
        }
        return start
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let h = Int(interval / 3600)
        let m = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(h)h \(m)m"
    }
}

private struct SummaryStoryCard: View {
    let eventId: String
    let created: Bool
    let photoCount: Int
    let previews: [StoryAsset]
    let savedVideo: URL?
    @State private var showingVideo = false
    @Namespace private var photoTransition

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            NavigationLink(value: Route.stories(eventId)) {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColors.accentWarm)
                        .frame(width: 42, height: 42)
                        .background(AppColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(created ? "Your photo timeline" : "Create photo timeline").font(.headline)
                        Text(photoCount > 0 ? "\(photoCount) \(photoCount == 1 ? "moment" : "moments") from Photos" : "Replay the night with your photos and clips.")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RecapPressStyle())

            if !previews.isEmpty {
                HStack(spacing: 6) {
                    ForEach(previews) { asset in
                        SummaryStoryPreview(eventId: eventId, asset: asset, namespace: photoTransition)
                    }
                }
                .frame(height: 108)
            }

            if savedVideo != nil {
                Button { showingVideo = true } label: {
                    HStack {
                        Label("Play saved video", systemImage: "play.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.accentWarm)
                        Spacer()
                        Text("On this device")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(10)
                    .background(AppColors.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(RecapPressStyle())
            }
        }
        .padding(16)
        .premiumCard(radius: 16)
        .fullScreenCover(isPresented: $showingVideo) {
            if let savedVideo { StoryMoviePreview(url: savedVideo) }
        }
    }
}

private struct SummaryStoryPreview: View {
    let eventId: String
    let asset: StoryAsset
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?

    var body: some View {
        NavigationLink {
            let destination = StoriesView(eventId: eventId, openingPhoto: StoryOpeningPhoto(asset: asset, image: image))
            if reduceMotion {
                destination
            } else {
                destination.navigationTransition(.zoom(sourceID: asset.id, in: namespace))
            }
        } label: {
            GeometryReader { geometry in
                ZStack(alignment: .bottomTrailing) {
                    AppColors.surfaceElevated
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .transition(reduceMotion ? .identity : .opacity)
                    }
                    if asset.isVideo {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.65), in: Circle())
                            .padding(6)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .matchedTransitionSource(id: asset.id, in: namespace)
        }
        .buttonStyle(RecapPressStyle())
        .accessibilityLabel("Open \(asset.isVideo ? "clip" : "photo") at \(NightReview.time(asset.timestamp))")
        .task(id: asset.id) {
            for await thumbnail in PhotoLibraryService.thumbnail(for: asset.id, size: CGSize(width: 420, height: 740)) {
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion || image != nil ? nil : .easeOut(duration: 0.20)) {
                    image = thumbnail
                }
            }
        }
    }
}

private struct RecapPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.83 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct SummaryHighlightsCard: View {
    let highlights: [NightReview.Highlight]
    let onSelect: (NightReview.Highlight) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key moments").font(.headline)
            ForEach(highlights) { highlight in
                Button { onSelect(highlight) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: highlight.icon)
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(highlight.title).font(.subheadline.weight(.semibold))
                            Text(highlight.detail)
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RecapPressStyle())
                .accessibilityHint("Show these times on the chart")
            }
        }
        .padding(16)
        .premiumCard(radius: 14)
    }
}

private struct SummaryComparisonCard: View {
    let comparison: NightReview.Comparison

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compared with your last \(comparison.count) nights").font(.headline)
            comparisonRow("Standard drinks per hour", value: comparison.pace, usual: comparison.usualPace)
            comparisonRow("Glasses of water per drink", value: comparison.water, usual: comparison.usualWater)
            Text("Pace uses the full logged duration. Your usual is the median. One glass is 250 mL.")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(16)
        .premiumCard(radius: 14)
    }

    private func comparisonRow(_ title: String, value: Double, usual: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(String(format: "%.1f this night · %.1f usual", value, usual))
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummaryLogCard: View {
    let review: NightReview
    let drinkTypes: [DrinkType]

    var body: some View {
        let drinks = review.entries.map { entry in
            let name = drinkTypes.first { $0.id == entry.drinkTypeId }?.name ?? "Drink"
            return (id: "drink-\(entry.id)", date: entry.timestamp, label: entry.quantity > 1 ? "\(name) ×\(entry.quantity)" : name)
        }
        let water = review.waters.map { (id: "water-\($0.id)", date: $0.timestamp, label: "Water · \(Int($0.volumeMl)) mL") }
        let food = review.foods.map { (id: "food-\($0.id)", date: $0.timestamp, label: $0.type.displayName) }
        let log = (drinks + water + food).sorted { $0.date < $1.date }
        if !log.isEmpty {
            DisclosureGroup {
                ForEach(log, id: \.id) { row in
                    HStack {
                        Text(row.label)
                        Spacer()
                        Text(row.date, format: .dateTime.hour().minute())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .font(.subheadline)
                    .padding(.top, 8)
                }
            } label: {
                Text("View log").font(.headline)
            }
            .padding(16)
            .premiumCard(radius: 14)
        }
    }
}

private struct CalorieEquivalenciesCard: View {
    let calories: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.accentWarm)
                    .frame(width: 44, height: 44)
                    .background(AppColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Drink calories").font(.headline)
                    Text("Estimated exercise equivalents")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 4)
                Text("\(Int(calories)) kcal")
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(AppColors.accentWarm)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ActivityEquivalence.allCases, id: \.self) { activity in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(activity.name, systemImage: activity.icon)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColors.textSecondary)
                        Text(activity.duration(calories: calories))
                            .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(AppColors.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppColors.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Text("Estimates use fixed activity rates. Actual energy use varies.")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .premiumCard(radius: 14)
        .padding(.horizontal)
    }
}

// MARK: - Share Card

private struct SummaryShareCard: View {
    let event: NightEvent
    let meanBAC: Double
    let drinkCount: Int
    let standardDrinks: Double
    let timeline: [BACDataPoint]
    let calories: Double
    let waterCount: Int

    private let cardW: CGFloat = 390
    private let cardH: CGFloat = 693

    private var stage: IntoxicationStage { IntoxicationStage.stage(for: meanBAC) }
    private var peakBAC: Double { timeline.map(\.bac).max() ?? meanBAC }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: event.startTime)
    }

    private var durationStr: String {
        let d = event.duration
        let h = Int(d / 3600)
        let m = Int(d.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var hourlyData: [(label: String, bac: Double)] {
        guard !timeline.isEmpty else { return [] }
        let sorted = timeline.sorted { $0.date < $1.date }
        let start = event.startTime
        let end = event.endTime ?? sorted.last?.date ?? Date()
        let totalHours = max(Int(ceil(end.timeIntervalSince(start) / 3600)), 1)
        let fmt = DateFormatter()
        fmt.dateFormat = "ha"
        return (0...totalHours).map { h in
            let t = start.addingTimeInterval(Double(h) * 3600)
            let bac = BACCalculator.interpolatedBAC(at: t, sorted: sorted)
            return (label: fmt.string(from: t).lowercased(), bac: max(0, bac))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.04, green: 0.04, blue: 0.07)
                .ignoresSafeArea()

            // Top stage-color sunrise wash
            LinearGradient(
                colors: [stage.color.opacity(0.40), stage.color.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)

            VStack(spacing: 0) {
                // Branding row
                HStack {
                    HStack(spacing: 8) {
                        if let icon = UIImage(named: "AppIcon") {
                            Image(uiImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .cornerRadius(5)
                        }
                        Text("TRACKSIP")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(2.5)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    Text(formattedDate)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 28)
                .padding(.top, 54)

                Spacer().frame(height: 22)

                // Event name
                Text(event.displayName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)

                Text("\(durationStr) night out")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 3)

                Spacer().frame(height: 26)

                // Hero BAC
                ZStack {
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [stage.color.opacity(0.55), .clear],
                            center: .center, startRadius: 0, endRadius: 88
                        ))
                        .frame(width: 210, height: 105)
                        .blur(radius: 28)

                    VStack(spacing: 5) {
                        Text(String(format: "%.3f%%", meanBAC))
                            .font(.system(size: 60, weight: .black, design: .monospaced))
                            .foregroundStyle(stage.color)
                            .shadow(color: stage.color.opacity(0.8), radius: 24, x: 0, y: 0)

                        Text("MEAN BAC  ·  " + stage.name.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(stage.color.opacity(0.65))
                    }
                }

                Spacer().frame(height: 28)

                // Hourly BAC chart section
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR NIGHT, HOUR BY HOUR")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.28))
                        .padding(.leading, 2)

                    ShareHourlyChart(data: hourlyData, peakBAC: peakBAC)
                        .frame(height: 144)
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 22)

                // Stats pill
                HStack(spacing: 0) {
                    ShareMiniStat(emoji: "🍹", value: "\(drinkCount)", label: "drinks")
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 36)
                    ShareMiniStat(emoji: "🔥", value: "\(Int(calories))", label: "cal")
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 36)
                    ShareMiniStat(emoji: "💧", value: "\(waterCount)", label: "water")
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 36)
                    ShareMiniStat(emoji: "🥃", value: String(format: "%.1f", standardDrinks), label: "std")
                }
                .padding(.vertical, 16)
                .background(.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 24)

                Spacer()

                Text("tracked with TrackSip")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.15))
                    .padding(.bottom, 46)
            }
        }
        .frame(width: cardW, height: cardH)
    }
}

private struct ShareHourlyChart: View {
    let data: [(label: String, bac: Double)]
    let peakBAC: Double

    private var peakIdx: Int? {
        data.indices.max(by: { data[$0].bac < data[$1].bac })
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let n = max(data.count, 1)
                let gap: CGFloat = 4
                let barW = (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                let yMax = max(peakBAC * 1.15, 0.01)
                let chartH = geo.size.height

                ZStack(alignment: .bottomLeading) {
                    // Grid lines
                    Canvas { ctx, size in
                        for frac in [CGFloat(0.25), 0.50, 0.75] {
                            let y = size.height * (1 - frac)
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            ctx.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 0.5)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bars
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(0..<n, id: \.self) { i in
                            let item = data[i]
                            let stg = IntoxicationStage.stage(for: item.bac)
                            let barH = max(CGFloat(item.bac / yMax) * chartH, item.bac > 0 ? 3 : 0)

                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: min(barW * 0.35, 5))
                                    .fill(LinearGradient(
                                        colors: [stg.color, stg.color.opacity(0.45)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .frame(width: barW, height: barH)

                                if barH > 10 {
                                    RoundedRectangle(cornerRadius: min(barW * 0.35, 5))
                                        .fill(.white.opacity(0.12))
                                        .frame(width: barW, height: min(barH * 0.35, 14))
                                }
                            }
                            .frame(width: barW, height: barH)
                            .overlay(alignment: .top) {
                                if i == peakIdx && item.bac > 0 {
                                    Text(String(format: "%.3f", item.bac))
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(stg.color)
                                        .offset(y: -13)
                                }
                            }
                        }
                    }
                }
            }

            // Hour labels
            HStack(spacing: 4) {
                ForEach(0..<data.count, id: \.self) { i in
                    Text(data[i].label)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.28))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        }
    }
}

private struct ShareMiniStat: View {
    let emoji: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(emoji)
                .font(.system(size: 18))
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Drinking Pace helper + card

/// Per-drink sipping duration: min(effectiveDrinkingMinutes, gap to next drink).
struct DrinkSipResult {
    let entry: DrinkEntry
    let drinkType: DrinkType?
    let sipMinutes: Int
}

func drinkSipDurations(entries: [DrinkEntry], drinkTypes: [DrinkType]) -> [DrinkSipResult] {
    let sorted = entries.sorted { $0.timestamp < $1.timestamp }
    return sorted.enumerated().map { i, entry in
        let dt      = drinkTypes.first { $0.id == entry.drinkTypeId }
        let natural = dt?.effectiveDrinkingMinutes ?? 20
        let sipMin: Int
        if i + 1 < sorted.count {
            let gap = Int(sorted[i + 1].timestamp.timeIntervalSince(entry.timestamp) / 60)
            sipMin = gap > 0 ? min(natural, gap) : natural
        } else {
            sipMin = natural
        }
        return DrinkSipResult(entry: entry, drinkType: dt, sipMinutes: sipMin)
    }
}
