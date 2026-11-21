import Foundation
import Testing
@testable import siptrack

/// The admin photo review screen's pure pieces: who sees the row, how the
/// callables' answers are read, and what a row shows and allows.
@MainActor
struct PhotoReviewTests {
    private func row(_ changes: [String: Any?] = [:]) -> [String: Any] {
        var all: [String: Any] = [
            "id": "chilaquiles-mx", "name": "Chilaquiles verdes", "kind": "breakfast",
            "countries": ["MX"], "photoUrl": "https://example.com/a.jpg", "photoStatus": "ready",
        ]
        for (key, value) in changes {
            if let value { all[key] = value } else { all.removeValue(forKey: key) }
        }
        return all
    }

    private func item(status: String, url: String? = "https://example.com/a.jpg",
                      kind: String = "breakfast", countries: [String] = ["MX"]) -> PendingPhoto {
        PendingPhoto(id: "i", name: "Item", kind: kind, countries: countries,
                     photoUrl: url.flatMap { URL(string: $0) }, photoStatus: status)
    }

    // MARK: - Who sees the row

    @Test func onlyAListedUidSeesTheReviewRow() {
        let admins: Set<String> = ["owner-uid"]
        #expect(AdminAccess.canReviewPhotos(uid: "owner-uid", admins: admins))
        #expect(!AdminAccess.canReviewPhotos(uid: "someone-else", admins: admins))
        #expect(!AdminAccess.canReviewPhotos(uid: nil, admins: admins))
        #expect(!AdminAccess.canReviewPhotos(uid: "", admins: admins))
        #expect(!AdminAccess.canReviewPhotos(uid: "owner-uid", admins: []))
    }

    @Test func actionsAreTheServersStrings() {
        #expect(PhotoReviewAction.allCases.map(\.rawValue) == ["approve", "reject", "regenerate"])
    }

    // MARK: - listPendingPhotos

    @Test func pendingListIsReadInTheServersOrder() {
        let result: [String: Any] = ["items": [row(), row(["id": "walk", "name": "Slow walk", "kind": "activity",
                                                           "countries": ["*"]])]]
        let items = PendingPhoto.list(from: result)
        #expect(items.map(\.id) == ["chilaquiles-mx", "walk"])
        #expect(items[0] == PendingPhoto(id: "chilaquiles-mx", name: "Chilaquiles verdes", kind: "breakfast",
                                         countries: ["MX"], photoUrl: URL(string: "https://example.com/a.jpg"),
                                         photoStatus: "ready"))
        #expect(items[1].kind == "activity")
        #expect(items[1].countries == ["*"])
    }

    @Test func aRowWithoutAnIdIsSkipped() {
        let result: [String: Any] = ["items": [row(["id": nil]), row(["id": ""]), row()]]
        #expect(PendingPhoto.list(from: result).map(\.id) == ["chilaquiles-mx"])
    }

    @Test func aNullPhotoAndMissingFieldsAreTolerated() {
        let parsed = PendingPhoto(row: row(["photoUrl": NSNull(), "name": nil, "countries": nil,
                                            "photoStatus": "generating"]))
        #expect(parsed?.photoUrl == nil)
        #expect(parsed?.name == "chilaquiles-mx")
        #expect(parsed?.countries.isEmpty == true)
        #expect(parsed?.photoStatus == "generating")
        #expect(PendingPhoto(row: row(["photoUrl": ""]))?.photoUrl == nil)
    }

    @Test func aMissingOrMalformedListIsEmpty() {
        #expect(PendingPhoto.list(from: [:]).isEmpty)
        #expect(PendingPhoto.list(from: ["items": "nope"]).isEmpty)
    }

    // MARK: - reviewPhoto regenerate

    @Test func regenerationReadsTheNewPhoto() {
        let done = PhotoRegeneration(result: ["ok": true, "photoStatus": "ready",
                                              "photoUrl": "https://example.com/v2.jpg"])
        #expect(done == PhotoRegeneration(photoStatus: "ready", photoUrl: URL(string: "https://example.com/v2.jpg")))
    }

    @Test func aFailedRegenerationIsReportedNotThrown() {
        let failed = PhotoRegeneration(result: ["ok": true, "photoStatus": "failed", "photoUrl": NSNull()])
        #expect(failed == PhotoRegeneration(photoStatus: "failed", photoUrl: nil))
    }

    @Test func anAnswerWithoutAStatusCountsAsFailed() {
        #expect(PhotoRegeneration(result: ["ok": true]).photoStatus == "failed")
        #expect(PhotoRegeneration(result: ["ok": true, "photoStatus": ""]).photoStatus == "failed")
    }

    @Test func aRegeneratedRowKeepsItsPlaceWithTheNewPhotoOrTheFailure() {
        let before = item(status: "ready")
        let after = before.updated(with: PhotoRegeneration(photoStatus: "ready",
                                                           photoUrl: URL(string: "https://example.com/v2.jpg")))
        #expect(after.id == before.id)
        #expect(after.name == before.name)
        #expect(after.photoUrl == URL(string: "https://example.com/v2.jpg"))
        let failed = before.updated(with: PhotoRegeneration(photoStatus: "failed", photoUrl: nil))
        #expect(failed.photoStatus == "failed")
        #expect(PhotoReview.badge(failed) == "Photo failed")
    }

    // MARK: - What a row shows

    @Test func countryAndKindLine() {
        #expect(PhotoReview.countryLabel(["MX"]) == "MX")
        #expect(PhotoReview.countryLabel(["US", "MX"]) == "US, MX")
        #expect(PhotoReview.countryLabel(["*"]) == "Everywhere")
        #expect(PhotoReview.countryLabel([]) == "No country")
        #expect(PhotoReview.detailLine(item(status: "ready")) == "Breakfast · MX")
        #expect(PhotoReview.detailLine(item(status: "ready", kind: "activity", countries: ["*"]))
                == "Activity · Everywhere")
        #expect(PhotoReview.detailLine(item(status: "ready", kind: "")) == "Item · MX")
    }

    @Test func badgeNamesEveryStateButAReadyPhoto() {
        #expect(PhotoReview.badge(item(status: "ready")) == nil)
        #expect(PhotoReview.badge(item(status: "ready", url: nil)) == "No photo")
        #expect(PhotoReview.badge(item(status: "generating", url: nil)) == "Generating")
        #expect(PhotoReview.badge(item(status: "failed")) == "Photo failed")
        #expect(PhotoReview.badge(item(status: "capped", url: nil)) == "No photo · daily cap")
    }

    @Test func onlyAReadyPhotoCanBeApproved() {
        #expect(PhotoReview.canApprove(item(status: "ready")))
        #expect(!PhotoReview.canApprove(item(status: "ready", url: nil)))
        #expect(!PhotoReview.canApprove(item(status: "failed")))
        #expect(!PhotoReview.canApprove(item(status: "generating")))
        #expect(!PhotoReview.canApprove(item(status: "capped", url: nil)))
    }

    // MARK: - Errors

    private func callableError(_ status: String?, message: String = "Admins only.") -> NSError {
        var info: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let status { info[FirebaseManager.callableStatusKey] = status }
        return NSError(domain: "FirebaseManager", code: 403, userInfo: info)
    }

    @Test func aRefusalFromTheAdminCheckIsExplained() {
        let expected = "This account is not on the server's admin list (ADMIN_UIDS)."
        #expect(PhotoReview.errorMessage(callableError("PERMISSION_DENIED")) == expected)
        #expect(PhotoReview.errorMessage(callableError("permission-denied")) == expected)
    }

    @Test func aGoneItemSaysSo() {
        #expect(PhotoReview.errorMessage(callableError("NOT_FOUND", message: "No such item."))
                == "This item no longer exists. Pull to refresh.")
    }

    @Test func otherErrorsKeepTheirOwnMessage() {
        #expect(PhotoReview.errorMessage(callableError("INTERNAL", message: "Boom.")) == "Boom.")
        #expect(PhotoReview.errorMessage(callableError(nil, message: "Server down.")) == "Server down.")
    }
}
