import SwiftUI
import AVKit
import UIKit

struct StoryOpeningPhoto {
    let asset: StoryAsset
    let image: UIImage?
}

struct StoriesView: View {
    let eventId: String
    let openingPhoto: StoryOpeningPhoto?
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var review: NightReview?
    @State private var assets: [StoryAsset] = []
    @State private var state = NightStoryState()
    @State private var momentId: String
    @State private var editor: StoryMoment?
    @State private var curating = false
    @State private var progress: Double?
    @State private var exportTask: Task<Void, Never>?
    @State private var movieURL: URL?
    @State private var previewing = false
    @State private var exportError: String?

    init(eventId: String, openingPhoto: StoryOpeningPhoto? = nil) {
        self.eventId = eventId
        self.openingPhoto = openingPhoto
        _momentId = State(initialValue: openingPhoto?.asset.id ?? "start")
    }

    private var story: NightStory? { review.map { NightStory(review: $0, assets: assets, state: state) } }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            if let story, !story.moments.isEmpty {
                let position = story.moments.firstIndex { $0.id == momentId } ?? 0
                let moment = story.moments[position]
                storyPage(story, position: position)
                tapZones(story, position: position)
                VStack(spacing: 4) {
                    progressRail(story: story, position: position)
                    header(story: story, moment: moment)
                    Spacer()
                    footer(moment: moment)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            } else if review == nil, let image = openingPhoto?.image {
                GeometryReader { geometry in
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            } else {
                emptyStory
            }
            if let progress {
                exportOverlay(progress)
            }
        }
        .foregroundStyle(AppColors.text)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .task(id: eventId) { await loadStory() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, review != nil { reloadAssets() }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
            guard openingPhoto == nil || reduceMotion, progress == nil else { return }
            if value.translation.height > 110, abs(value.translation.width) < 80 { dismiss() }
        })
        .sheet(item: $editor) { moment in
            StoryCaptionEditor(caption: state.captions[moment.id] ?? "", suggestion: story?.suggestions[moment.id]) { caption in
                state.setCaption(caption, for: moment.id)
                DataStore.shared.saveNightStoryState(state, eventId: eventId)
            }
        }
        .sheet(isPresented: $curating) {
            StoryCurationGrid(assets: assets, excluded: state.excludedAssetIds) { asset in
                if state.excludedAssetIds.contains(asset.id) {
                    state.excludedAssetIds.remove(asset.id)
                } else {
                    state.excludedAssetIds.insert(asset.id)
                }
                DataStore.shared.saveNightStoryState(state, eventId: eventId)
            } delete: { asset in
                NightPhotoStore.delete(asset)
                reloadAssets()
            }
        }
        .fullScreenCover(isPresented: $previewing) {
            if let movieURL { StoryMoviePreview(url: movieURL) }
        }
        .alert("Video export", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .onDisappear {
            exportTask?.cancel()
        }
    }

    private func loadStory() async {
        guard review == nil, let event = appState.events.first(where: { $0.id == eventId }) else { return }
        state = DataStore.shared.loadNightStoryState(eventId: eventId)
        movieURL = DataStore.shared.savedNightStoryVideo(eventId: eventId)
        review = appState.nightReview(for: event)
        reloadAssets()
    }

    private func reloadAssets() {
        guard let review else { return }
        assets = NightPhotoStore.assets(eventId: eventId)
        let hasMoments = review.drinkCount > 0 || assets.contains { !state.excludedAssetIds.contains($0.id) }
        if state.generatedAt == nil, hasMoments {
            state.generatedAt = .now
            DataStore.shared.saveNightStoryState(state, eventId: eventId)
        }
    }

    private func storyPage(_ story: NightStory, position: Int) -> some View {
        let moment = story.moments[position]
        let neighbors = [position - 1, position + 1].filter { story.moments.indices.contains($0) }
            .compactMap { story.moments[$0].asset }
        return GeometryReader { geometry in
            StoryPhotoPage(story: story, moment: moment, caption: state.captions[moment.id],
                           size: geometry.size, neighbors: neighbors, openingPhoto: openingPhoto)
        }
    }

    private func tapZones(_ story: NightStory, position: Int) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Button { move(to: position - 1, in: story, from: position) } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .accessibilityLabel("Previous moment")
                .frame(width: geometry.size.width * 0.32)
                Button { move(to: position + 1, in: story, from: position) } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .accessibilityLabel("Next moment")
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 84)
        .padding(.bottom, 55)
    }

    private func move(to position: Int, in story: NightStory, from current: Int) {
        guard story.moments.indices.contains(position), position != current else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.30)) {
            momentId = story.moments[position].id
        }
        Haptics.shared.play(.storyAdvance(bacDelta: abs(story.moments[position].bac - story.moments[current].bac)))
    }

    private func progressRail(story: NightStory, position: Int) -> some View {
        let count = story.moments.count
        return GeometryReader { geometry in
            Group {
                if count > 16 {
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(AppColors.accentWarm)
                            .frame(width: geometry.size.width * CGFloat(position + 1) / CGFloat(count))
                    }
                    .frame(height: 3)
                } else {
                    HStack(spacing: 3) {
                        ForEach(0..<count, id: \.self) { segment in
                            Capsule()
                                .fill(segment == position ? AppColors.accentWarm : .white.opacity(segment < position ? 0.8 : 0.25))
                                .frame(height: 3)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                let fraction = min(1, max(0, point.x / max(1, geometry.size.width)))
                move(to: min(count - 1, Int(fraction * CGFloat(count))), in: story, from: position)
            }
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Story progress")
        .accessibilityValue("Moment \(position + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(to: position + 1, in: story, from: position)
            case .decrement: move(to: position - 1, in: story, from: position)
            @unknown default: break
            }
        }
    }

    private func header(story: NightStory, moment: StoryMoment) -> some View {
        HStack {
            iconButton("xmark", label: "Close story") { dismiss() }
            Spacer()
            Menu {
                Button("Edit caption", systemImage: "text.bubble") { editor = moment }
                if !assets.isEmpty {
                    Button("Choose photos", systemImage: "square.grid.2x2") { curating = true }
                }
            } label: {
                controlIcon("ellipsis")
            }
            .accessibilityLabel("Story options")
            if movieURL != nil {
                Menu {
                    Button("Play saved video", systemImage: "play.fill") { previewing = true }
                    Button("Create updated video", systemImage: "arrow.clockwise") { startExport(story) }
                } label: {
                    controlIcon("film")
                }
                .accessibilityLabel("Story video")
            } else {
                iconButton("film", label: "Create video") { startExport(story) }
            }
        }
    }

    private func footer(moment: StoryMoment) -> some View {
        HStack {
            Spacer()
            iconButton("text.bubble", label: "Edit caption") { editor = moment }
        }
        .buttonStyle(.plain)
    }

    private var emptyStory: some View {
        VStack(spacing: 14) {
            if review == nil, appState.events.contains(where: { $0.id == eventId }) {
                ProgressView()
            } else {
                Image(systemName: "photo.on.rectangle").font(.system(size: 30))
                Text("No moments to show").font(.headline)
                Text("Tap the camera during a night to take photos. They show up here with your BAC at that moment.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                if !assets.isEmpty { Button("Choose photos") { curating = true } }
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            controlIcon(icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func controlIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.56), in: Circle())
    }

    private func exportOverlay(_ progress: Double) -> some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 15) {
                Text("Preparing your video").font(.headline)
                ProgressView(value: progress).tint(AppColors.accentWarm)
                Button("Cancel") { exportTask?.cancel() }.buttonStyle(.bordered)
            }
            .padding(22)
            .frame(maxWidth: 310)
            .premiumCard(radius: 18)
        }
    }

    private func startExport(_ story: NightStory) {
        guard exportTask == nil else { return }
        progress = 0
        exportTask = Task {
            defer {
                progress = nil
                exportTask = nil
            }
            do {
                let temporaryVideo = try await StoryVideoExporter.export(story: story, state: state) { progress = $0 }
                defer { try? FileManager.default.removeItem(at: temporaryVideo) }
                try Task.checkCancellation()
                movieURL = try DataStore.shared.saveNightStoryVideo(from: temporaryVideo, eventId: eventId)
                Haptics.shared.play(.exportDone)
                previewing = true
            } catch is CancellationError {
                return
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

}

private struct StoryPhotoPage: View {
    let story: NightStory
    let moment: StoryMoment
    let caption: String?
    let size: CGSize
    let neighbors: [StoryAsset]
    let openingPhoto: StoryOpeningPhoto?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var images: [String: UIImage] = [:]

    private var targetSize: CGSize {
        CGSize(width: max(1, size.width * displayScale), height: max(1, size.height * displayScale))
    }

    private var image: UIImage? {
        guard let id = moment.asset?.id else { return nil }
        return images[id] ?? (openingPhoto?.asset.id == id ? openingPhoto?.image : nil)
    }

    var body: some View {
        StoryCardView(story: story, moment: moment, image: image, caption: caption)
            .task(id: moment.id) {
                guard let asset = moment.asset else { return }
                for await thumbnail in NightPhotoStore.thumbnail(for: asset.id, size: targetSize) {
                    guard !Task.isCancelled else { return }
                    let current = image
                    if let current, current.size.width * current.size.height > thumbnail.size.width * thumbnail.size.height {
                        continue
                    }
                    withAnimation(reduceMotion || current != nil ? nil : .easeOut(duration: 0.20)) {
                        images[asset.id] = thumbnail
                    }
                }
            }
            .task(id: [moment.id] + neighbors.map(\.id)) {
                let retained = Set(neighbors.map(\.id) + [moment.id])
                images = images.filter { retained.contains($0.key) }
                for asset in neighbors where images[asset.id] == nil {
                    for await thumbnail in NightPhotoStore.thumbnail(for: asset.id, size: targetSize) {
                        guard !Task.isCancelled else { return }
                        images[asset.id] = thumbnail
                    }
                }
            }
    }
}

private struct StoryCaptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State var caption: String
    @State var suggestion: String?
    let save: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Write a caption", text: $caption)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onChange(of: caption) { _, text in
                        if text.count > 90 { caption = String(text.prefix(90)) }
                    }
                Text("\(caption.count)/90").font(.caption).foregroundStyle(AppColors.textSecondary)
                if let suggestion {
                    HStack(alignment: .top) {
                        Button {
                            caption = String(suggestion.prefix(90))
                            self.suggestion = nil
                        } label: {
                            Label(suggestion, systemImage: "sparkle").multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Button { self.suggestion = nil } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Dismiss suggestion")
                    }
                    .font(.subheadline)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(caption)
                        dismiss()
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

private struct StoryCurationGrid: View {
    let assets: [StoryAsset]
    let excluded: Set<String>
    let toggle: (StoryAsset) -> Void
    let delete: (StoryAsset) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(assets) { asset in
                        Button { toggle(asset) } label: {
                            StoryThumbnail(asset: asset, included: !excluded.contains(asset.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(excluded.contains(asset.id) ? "Include" : "Remove") photo at \(NightReview.time(asset.timestamp))")
                        .contextMenu {
                            Button("Delete photo", systemImage: "trash", role: .destructive) { delete(asset) }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Story photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct StoryThumbnail: View {
    let asset: StoryAsset
    let included: Bool
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                AppColors.surface
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(included ? 1 : 0.35)
                }
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(included ? AppColors.accentWarm : .white)
                    .padding(7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: asset.id) {
            for await thumbnail in NightPhotoStore.thumbnail(for: asset.id, size: CGSize(width: 260, height: 260)) {
                guard !Task.isCancelled else { return }
                image = thumbnail
            }
        }
    }
}

struct StoryMoviePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var sharing = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your night video").font(.headline)
                    Label("Saved on this device", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            VideoPlayer(player: player)
            Button {
                player?.pause()
                // Free too: taking the photos and exporting the video were
                // already unpaid, so charging only for the share button put the
                // paywall at the one step that costs us nothing and left the
                // user holding a video they could not send anywhere.
                sharing = true
            } label: {
                Label("Share video", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
        }
        .padding()
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            if player == nil { player = AVPlayer(url: url) }
            player?.play()
        }
        .onDisappear { player?.pause() }
        .sheet(isPresented: $sharing) { ShareSheet(items: [url]) }
    }
}
