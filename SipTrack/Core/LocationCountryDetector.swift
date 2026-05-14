import Foundation
import CoreLocation

// Result of one country detection pass.
enum CountryDetectionResult: Equatable, Identifiable {
    // We got a country and it matches our LegalBACLimits table.
    case matched(LegalBACLimit)
    // We got a country but we don't have data for it.
    case unknownCountry(code: String, name: String)

    var id: String {
        switch self {
        case .matched(let c):          return "m-\(c.countryCode)"
        case .unknownCountry(let c, _): return "u-\(c)"
        }
    }
}

// One-shot location → reverse-geocode → country lookup, so we can offer the
// user the legally accurate BAC limit when they open the app from a country
// other than the one their device locale claims.
//
// Privacy posture: we ask for *when in use* only, take a single coarse fix
// (kCLLocationAccuracyKilometer is enough to disambiguate countries), reverse
// geocode it through Apple's geocoder, then discard the coordinate. The
// raw CLLocation never leaves this object. We never start continuous updates.
@MainActor
final class LocationCountryDetector: NSObject, ObservableObject {

    @Published private(set) var result: CountryDetectionResult?
    @Published private(set) var status: CLAuthorizationStatus
    @Published private(set) var isRequesting = false
    @Published private(set) var lastError: String?
    // Set when the user has denied or restricted location; UI surfaces a hint
    // that they can still set the country manually in Profile.
    @Published private(set) var permissionDenied = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var hasRequestedThisSession = false

    override init() {
        self.status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // Public entry point. Idempotent within a session.
    func requestOnce() {
        guard !hasRequestedThisSession else { return }
        hasRequestedThisSession = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // The delegate callback will continue once the user decides.
        case .authorizedWhenInUse, .authorizedAlways:
            startFix()
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            break
        }
    }

    func dismissResult() { result = nil }

    // Called by the AppState when the user disables future prompts.
    func disable() {
        result = nil
        hasRequestedThisSession = true
    }

    // Re-arms the detector after a logout/login cycle so the next
    // `requestOnce()` actually fires. Does NOT clear permission state.
    func resetSession() {
        hasRequestedThisSession = false
        result = nil
        lastError = nil
    }

    private func startFix() {
        isRequesting = true
        manager.requestLocation()
    }

    private func reverseGeocode(_ location: CLLocation) {
        Task { @MainActor in
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                isRequesting = false
                guard let p = placemarks.first, let iso = p.isoCountryCode else {
                    lastError = "No country in geocoder response"
                    return
                }
                if let match = LegalBACLimits.find(iso) {
                    result = .matched(match)
                } else {
                    result = .unknownCountry(code: iso, name: p.country ?? iso)
                }
            } catch {
                isRequesting = false
                lastError = error.localizedDescription
            }
        }
    }
}

extension LocationCountryDetector: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus
        Task { @MainActor in
            self.status = s
            switch s {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.hasRequestedThisSession, !self.isRequesting, self.result == nil {
                    self.startFix()
                }
            case .denied, .restricted:
                self.permissionDenied = true
                self.isRequesting = false
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.reverseGeocode(loc)
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isRequesting = false
            self.lastError = error.localizedDescription
        }
    }
}
