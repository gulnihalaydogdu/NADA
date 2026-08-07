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
}
