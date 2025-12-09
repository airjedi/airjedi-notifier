import Foundation

struct Coordinate: Equatable, Codable {
    let latitude: Double
    let longitude: Double

    /// Calculate distance to another coordinate in nautical miles
    func distance(to other: Coordinate) -> Double {
        let earthRadiusNm = 3440.065

        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1) * cos(lat2) *
                sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusNm * c
    }
}
