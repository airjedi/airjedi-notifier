import Foundation

struct Aircraft: Identifiable, Equatable {
    let icaoHex: String
    var callsign: String?
    var position: Coordinate?
    var altitudeFeet: Int?
    var headingDegrees: Double?
    var speedKnots: Double?
    var verticalRateFpm: Double?
    var squawk: String?
    var lastSeen: Date

    // Enriched data
    var registration: String?
    var aircraftTypeCode: String?
    var operatorName: String?

    var id: String { icaoHex }

    /// Distance from a reference point in nautical miles
    func distance(from reference: Coordinate) -> Double? {
        guard let position = position else { return nil }
        return reference.distance(to: position)
    }
}
