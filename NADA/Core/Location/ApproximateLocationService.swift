import CoreLocation
import Foundation
import MapKit

/// One-shot approximate location for city + coarse lat/lng (no precise pin).
@MainActor
final class ApproximateLocationService: NSObject, CLLocationManagerDelegate {
    struct Result: Sendable {
        var city: String?
        var latitude: Double
        var longitude: Double
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if #available(iOS 14.0, *) {
            manager.desiredAccuracy = kCLLocationAccuracyReduced
        }
    }

    func requestApproximatePlace() async throws -> Result {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            try await waitForAuthorization()
        case .denied, .restricted:
            throw AuthError.unknown("Location permission is off. You can type your city instead.")
        default:
            break
        }

        let location = try await requestLocation()
        let latitude = ProfileLocation.coarsenCoordinate(location.coordinate.latitude)
        let longitude = ProfileLocation.coarsenCoordinate(location.coordinate.longitude)
        let city = try await reverseGeocodeCity(latitude: latitude, longitude: longitude)

        return Result(city: city, latitude: latitude, longitude: longitude)
    }

    private func reverseGeocodeCity(latitude: Double, longitude: Double) async throws -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else {
                return nil
            }
            let mapItems = try await request.mapItems
            guard let item = mapItems.first else { return nil }
            let representations = item.addressRepresentations
            return representations?.cityName
                ?? representations?.cityWithContext
                ?? representations?.regionName
                ?? item.name
        } else {
            // Pre–iOS 26 fallback (only compiled for older OS paths).
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.locality
                ?? placemarks.first?.subAdministrativeArea
                ?? placemarks.first?.administrativeArea
        }
    }

    private func waitForAuthorization() async throws {
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                return
            }
            if status == .denied || status == .restricted {
                throw AuthError.unknown("Location permission is off. You can type your city instead.")
            }
        }
        throw AuthError.unknown("Location permission timed out. You can type your city instead.")
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            continuation?.resume(returning: location)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
