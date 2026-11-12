import Foundation
import Testing
@testable import siptrack

struct AppStoreUpdateTests {
    private let bundleID = "com.lorenzoog.siptrack"

    @Test func newerVersionUsesNumericComponents() throws {
        let update = try available(published: "1.10", installed: "1.9.5")
        #expect(update?.version == "1.10")
    }

    @Test func sameOrOlderListingDoesNotPrompt() throws {
        let equal = try available(published: "1.2", installed: "1.2.0")
        let older = try available(published: "1.2.9", installed: "1.3")
        #expect(equal == nil)
        #expect(older == nil)
    }

    @Test func newerVersionRequiresACompatibleDevice() throws {
        let compatible = try available(published: "1.3", installed: "1.2", minimumOS: "18.2", systemOS: "18.2.0")
        let incompatible = try available(published: "1.3", installed: "1.2", minimumOS: "19.0", systemOS: "18.6")
        #expect(compatible?.version == "1.3")
        #expect(incompatible == nil)
    }

    @Test func ignoresUnavailableOrInvalidListings() throws {
        let empty = try AppStoreUpdate.available(
            in: Data(#"{"resultCount":0,"results":[]}"#.utf8),
            bundleID: bundleID, installedVersion: "1.2", systemVersion: "18.0"
        )
        let malformed = try available(published: "1..3", installed: "1.2")
        let otherApp = try available(published: "1.3", installed: "1.2", listingBundleID: "com.other.app")
        #expect(empty == nil)
        #expect(malformed == nil)
        #expect(otherApp == nil)
    }

    @Test func convertsStorefrontCountryCodesForLookup() {
        #expect(AppStoreUpdate.lookupCountryCode("MEX") == "mx")
        #expect(AppStoreUpdate.lookupCountryCode("GBR") == "gb")
        #expect(AppStoreUpdate.lookupCountryCode("US") == "us")
        #expect(AppStoreUpdate.lookupCountryCode("419") == nil)
    }

    @Test func blocksOnlyVersionsBelowTheMinimum() {
        #expect(RequiredUpdate.isRequired(installed: "1.0.32", minimum: "1.0.33"))
        #expect(RequiredUpdate.isRequired(installed: "1.9", minimum: "1.10"))
        #expect(!RequiredUpdate.isRequired(installed: "1.0.33", minimum: "1.0.33"))
        #expect(!RequiredUpdate.isRequired(installed: "1.0.33", minimum: "1.0.33.0"))
        #expect(!RequiredUpdate.isRequired(installed: "1.1", minimum: "1.0.40"))
    }

    @Test func missingOrMalformedMinimumNeverBlocks() {
        #expect(!RequiredUpdate.isRequired(installed: "1.0.32", minimum: nil))
        #expect(!RequiredUpdate.isRequired(installed: "1.0.32", minimum: ""))
        #expect(!RequiredUpdate.isRequired(installed: "1.0.32", minimum: "1.0.x"))
        #expect(!RequiredUpdate.isRequired(installed: "1.0.32", minimum: "v1.1"))
    }

    private func available(
        published: String, installed: String, minimumOS: String = "18.0",
        systemOS: String = "18.0", listingBundleID: String = "com.lorenzoog.siptrack"
    ) throws -> AppStoreUpdate? {
        let json = #"""
        {"results":[{"trackId":6762666633,"bundleId":"\#(listingBundleID)","version":"\#(published)","minimumOsVersion":"\#(minimumOS)"}]}
        """#
        return try AppStoreUpdate.available(
            in: Data(json.utf8), bundleID: bundleID, installedVersion: installed, systemVersion: systemOS
        )
    }
}
