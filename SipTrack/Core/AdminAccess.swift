import Foundation

/// Who sees the hidden Review photos screen in Profile. Hiding the row is a
/// convenience only: the review callables check the server's `ADMIN_UIDS`
/// on every call and refuse anyone else with `permission-denied`.
enum AdminAccess {
    /// The owner's Firebase uid (the same uid as the server's `ADMIN_UIDS`).
    static let uids: Set<String> = ["zmlidDcLE4VZnnE99d3m5diCEIJ2"]

    /// Whether this signed-in user gets the Review photos row.
    static func canReviewPhotos(uid: String?, admins: Set<String> = AdminAccess.uids) -> Bool {
        guard let uid, !uid.isEmpty else { return false }
        return admins.contains(uid)
    }
}

/// What the admin can do to a pending library photo (`reviewPhoto`'s `action`).
enum PhotoReviewAction: String, CaseIterable {
    case approve, reject, regenerate
}

/// One recovery library item whose photo awaits review, as
/// `listPendingPhotos` returns it.
struct PendingPhoto: Identifiable, Equatable {
    let id: String
    let name: String
    /// "breakfast" or "activity".
    let kind: String
    /// Country codes, or "*" for everywhere.
    let countries: [String]
    var photoUrl: URL?
    /// "ready", "generating", "failed" or "capped".
    var photoStatus: String

    /// Reads one row of `{items: [...]}`. Nil without an id, since the review
    /// call needs one.
    init?(row: [String: Any]) {
        guard let id = row["id"] as? String, !id.isEmpty else { return nil }
        self.id = id
        let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = name.isEmpty ? id : name
        kind = row["kind"] as? String ?? ""
        countries = row["countries"] as? [String] ?? []
        photoUrl = PhotoReview.url(row["photoUrl"])
        photoStatus = row["photoStatus"] as? String ?? ""
    }

    init(id: String, name: String, kind: String, countries: [String], photoUrl: URL?, photoStatus: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.countries = countries
        self.photoUrl = photoUrl
        self.photoStatus = photoStatus
    }

    /// `listPendingPhotos`' answer, in the server's order (newest first).
    static func list(from result: [String: Any]) -> [PendingPhoto] {
        (result["items"] as? [[String: Any]] ?? []).compactMap { PendingPhoto(row: $0) }
    }

    /// The row after a regeneration: the item stays pending, with its new
    /// photo, or with the "failed" status when no photo came.
    func updated(with regeneration: PhotoRegeneration) -> PendingPhoto {
        var copy = self
        copy.photoStatus = regeneration.photoStatus
        copy.photoUrl = regeneration.photoUrl
        return copy
    }
}

/// What a regeneration left behind: `reviewPhoto`'s answer to `regenerate`,
/// `{ok, photoStatus, photoUrl}`. A failed photo is reported, not thrown.
struct PhotoRegeneration: Equatable {
    let photoStatus: String
    let photoUrl: URL?

    init(photoStatus: String, photoUrl: URL?) {
        self.photoStatus = photoStatus
        self.photoUrl = photoUrl
    }

    /// An answer that names no status counts as a failure, so the row says so
    /// rather than claiming a photo that may not exist.
    init(result: [String: Any]) {
        let status = (result["photoStatus"] as? String) ?? ""
        photoStatus = status.isEmpty ? "failed" : status
        photoUrl = PhotoReview.url(result["photoUrl"])
    }
}

/// The review screen's small rules, kept pure so they are tested without the view.
enum PhotoReview {
    /// A photo URL from the server, which sends `null` when there is none.
    static func url(_ value: Any?) -> URL? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return URL(string: text)
    }

    /// `MX`, `US, MX`, or `Everywhere` for the shared set.
    static func countryLabel(_ countries: [String]) -> String {
        if countries.isEmpty { return "No country" }
        if countries.contains("*") { return "Everywhere" }
        return countries.joined(separator: ", ")
    }

    /// `Breakfast · MX`.
    static func detailLine(_ item: PendingPhoto) -> String {
        let kind = item.kind.isEmpty ? "Item" : item.kind.capitalized
        return "\(kind) · \(countryLabel(item.countries))"
    }

    /// The badge over the photo, or nil for a ready photo.
    static func badge(_ item: PendingPhoto) -> String? {
        switch item.photoStatus {
        case "ready" where item.photoUrl != nil: return nil
        case "generating": return "Generating"
        case "failed": return "Photo failed"
        case "capped": return "No photo · daily cap"
        default: return "No photo"
        }
    }

    /// Only a ready photo can be approved. An approved item without one would
    /// go live, unreviewed, the day a later run gives it a photo.
    static func canApprove(_ item: PendingPhoto) -> Bool {
        item.photoStatus == "ready" && item.photoUrl != nil
    }

    /// What a failed call says on screen. A refusal from the admin check gets
    /// a plain explanation; anything else keeps the callable's own message.
    static func errorMessage(_ error: Error) -> String {
        let status = ((error as NSError).userInfo[FirebaseManager.callableStatusKey] as? String)?
            .uppercased().replacingOccurrences(of: "-", with: "_")
        switch status {
        case "PERMISSION_DENIED"?:
            return "This account is not on the server's admin list (ADMIN_UIDS)."
        case "NOT_FOUND"?:
            return "This item no longer exists. Pull to refresh."
        default:
            return error.localizedDescription
        }
    }
}
