import Foundation

/// Discover distance clamps shared by `users/{uid}` and `preferences/{uid}` (W2-04 / W2-05 / W2-10).
enum ProfileLocation {
    static let defaultRadiusKm = 25
    static let minimumRadiusKm = 5
    static let maximumRadiusKm = 80
    static let radiusStepKm = 5

    static func clampRadiusKm(_ value: Int) -> Int {
        let stepped = (value / radiusStepKm) * radiusStepKm
        return min(max(stepped, minimumRadiusKm), maximumRadiusKm)
    }

    static func clampRadiusKm(_ value: Double) -> Int {
        clampRadiusKm(Int(value.rounded()))
    }

    /// ~city-level precision (~1 km); never store full GPS precision.
    static func coarsenCoordinate(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// Great-circle distance in km between two WGS84 points (Haversine).
    static func distanceKm(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let dLat = (toLatitude - fromLatitude) * .pi / 180
        let dLon = (toLongitude - fromLongitude) * .pi / 180
        let lat1 = fromLatitude * .pi / 180
        let lat2 = toLatitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }
}
