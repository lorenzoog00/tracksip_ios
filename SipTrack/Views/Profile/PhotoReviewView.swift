import SwiftUI

/// The hidden admin screen behind Profile → Review photos: recovery library
/// items whose photo awaits review, newest first, with Approve, Reject and
/// Regenerate. Only `AdminAccess.uids` see the row; the server checks its own
/// admin list on every call.
struct PhotoReviewView: View {
    @State private var items: [PendingPhoto] = []
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var loadError: String?
    /// The action running on each row, by item id. A row with one has its
    /// buttons disabled until it returns.
    @State private var running: [String: PhotoReviewAction] = [:]
    /// The last failed action's message on each row, by item id.
    @State private var rowErrors: [String: String] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let loadError {
                    ReviewErrorLine(text: loadError)
                }
                if hasLoaded && items.isEmpty && loadError == nil {
                    emptyState
                }
                ForEach(items) { item in
                    PendingPhotoCard(item: item, running: running[item.id], error: rowErrors[item.id]) { action in
                        Task { await review(item.id, action) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(AppColors.background.ignoresSafeArea())
        .overlay {
            if isLoading && !hasLoaded {
                ProgressView()
                    .tint(AppColors.accent)
            }
        }
        .navigationTitle("Review photos")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            guard !hasLoaded else { return }
            await load()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34))
                .foregroundStyle(AppColors.accent)
            Text("Nothing to review")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.text)
            Text("New library photos wait here until you approve or reject them.")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 24)
    }

    private func load() async {
        isLoading = true
        do {
            items = try await FirebaseManager.shared.listPendingPhotos()
            loadError = nil
        } catch {
            // Leaving the screen mid-refresh cancels the request; that is not an error.
            if !Task.isCancelled { loadError = PhotoReview.errorMessage(error) }
        }
        isLoading = false
        hasLoaded = true
    }

    /// Approve and reject remove the row on success. Regenerate keeps it and
    /// shows the new photo, or the "failed" badge when none came.
    private func review(_ id: String, _ action: PhotoReviewAction) async {
        guard running[id] == nil else { return }
        running[id] = action
        rowErrors[id] = nil
        do {
            let regeneration = try await FirebaseManager.shared.reviewPhoto(id: id, action: action)
            running[id] = nil
            if let regeneration {
                if let index = items.firstIndex(where: { $0.id == id }) {
                    items[index] = items[index].updated(with: regeneration)
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    items.removeAll { $0.id == id }
                }
            }
        } catch {
            running[id] = nil
            rowErrors[id] = PhotoReview.errorMessage(error)
        }
    }
}

/// One pending item: its photo, name and country, and the three actions.
private struct PendingPhotoCard: View {
    let item: PendingPhoto
    /// The action in flight on this row, if any.
    let running: PhotoReviewAction?
    let error: String?
    let onAction: (PhotoReviewAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            photo

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(PhotoReview.detailLine(item))
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
            }

            if let error {
                ReviewErrorLine(text: error)
            }

            HStack(spacing: 8) {
                actionButton(.approve, title: "Approve", icon: "checkmark",
                             tint: AppColors.success, enabled: PhotoReview.canApprove(item))
                actionButton(.reject, title: "Reject", icon: "xmark",
                             tint: AppColors.danger, enabled: true)
                actionButton(.regenerate, title: "Regenerate", icon: "arrow.clockwise",
                             tint: AppColors.accent, enabled: true)
            }
        }
        .padding(14)
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
    }

    /// The tile sets the size; the photo is an overlay so its fill can never
    /// widen the layout, and the clip trims it.
    private var photo: some View {
        AppColors.surfaceElevated
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                Image(systemName: item.kind == "activity" ? "figure.walk" : "fork.knife")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .overlay {
                if let url = item.photoUrl {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else if phase.error == nil {
                            ProgressView()
                                .tint(AppColors.accent)
                        }
                    }
                }
            }
            .overlay {
                if running == .regenerate {
                    ZStack {
                        Color.black.opacity(0.6)
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Regenerating · up to 2 minutes")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if running != .regenerate, let badge = PhotoReview.badge(item) {
                    Text(badge)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badgeColor, in: Capsule())
                        .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var badgeColor: Color {
        item.photoStatus == "failed" ? AppColors.danger : Color.black.opacity(0.7)
    }

    private func actionButton(_ action: PhotoReviewAction, title: String, icon: String,
                              tint: Color, enabled: Bool) -> some View {
        let dimmed = !enabled || (running != nil && running != action)
        return Button {
            onAction(action)
        } label: {
            HStack(spacing: 5) {
                if running == action {
                    ProgressView()
                        .controlSize(.small)
                        .tint(tint)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(running != nil || !enabled)
        .opacity(dimmed ? 0.4 : 1)
    }
}

/// An error shown in place, on the screen or on one row.
private struct ReviewErrorLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.danger)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.dangerDim, in: RoundedRectangle(cornerRadius: 10))
    }
}
