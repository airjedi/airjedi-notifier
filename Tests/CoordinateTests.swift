import XCTest
@testable import AirJedi

final class CoordinateTests: XCTestCase {

    // MARK: - Distance to Self

    func testDistanceToSelfIsZero() {
        let coord = Coordinate(latitude: 37.7749, longitude: -122.4194) // San Francisco
        let distance = coord.distance(to: coord)
        XCTAssertEqual(distance, 0, accuracy: 0.0001, "Distance from a point to itself should be zero")
    }

    // MARK: - Known Distances

    func testSFOToLAXDistance() {
        // SFO: 37.6213, -122.3790
        // LAX: 33.9425, -118.4081
        // Known distance: approximately 298 nautical miles
        let sfo = Coordinate(latitude: 37.6213, longitude: -122.3790)
        let lax = Coordinate(latitude: 33.9425, longitude: -118.4081)

        let distance = sfo.distance(to: lax)

        // Allow 5nm tolerance for Haversine approximation
        XCTAssertEqual(distance, 298, accuracy: 5, "SFO to LAX should be approximately 298 nm")
    }

    func testNewYorkToLondonDistance() {
        // JFK: 40.6413, -73.7781
        // LHR: 51.4700, -0.4543
        // Known distance: approximately 2999 nautical miles
        let jfk = Coordinate(latitude: 40.6413, longitude: -73.7781)
        let lhr = Coordinate(latitude: 51.4700, longitude: -0.4543)

        let distance = jfk.distance(to: lhr)

        // Allow 20nm tolerance for longer distances
        XCTAssertEqual(distance, 2999, accuracy: 20, "JFK to LHR should be approximately 2999 nm")
    }

    func testShortDistance() {
        // Two points about 1 nm apart
        let point1 = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let point2 = Coordinate(latitude: 37.7916, longitude: -122.4194) // ~1nm north

        let distance = point1.distance(to: point2)

        XCTAssertEqual(distance, 1.0, accuracy: 0.1, "Points ~1nm apart should measure approximately 1nm")
    }

    // MARK: - Antipodal Points

    func testAntipodalPointsDistance() {
        // Antipodal points are on opposite sides of the Earth
        // Maximum distance is half Earth's circumference: ~10800 nm
        let point1 = Coordinate(latitude: 0, longitude: 0)
        let antipode = Coordinate(latitude: 0, longitude: 180)

        let distance = point1.distance(to: antipode)

        // Half Earth circumference at equator is about 10800 nm
        XCTAssertEqual(distance, 10800, accuracy: 100, "Antipodal points should be ~10800 nm apart")
    }

    func testNorthPoleToSouthPoleDistance() {
        let northPole = Coordinate(latitude: 90, longitude: 0)
        let southPole = Coordinate(latitude: -90, longitude: 0)

        let distance = northPole.distance(to: southPole)

        // Pole to pole is half circumference: ~10800 nm
        XCTAssertEqual(distance, 10800, accuracy: 100, "Pole to pole should be ~10800 nm")
    }

    // MARK: - Symmetry

    func testDistanceSymmetry() {
        let coord1 = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let coord2 = Coordinate(latitude: 40.7128, longitude: -74.0060)

        let distance1 = coord1.distance(to: coord2)
        let distance2 = coord2.distance(to: coord1)

        XCTAssertEqual(distance1, distance2, accuracy: 0.0001, "Distance should be symmetric")
    }

    // MARK: - Edge Cases

    func testCrossDateLineDistance() {
        // Points on opposite sides of the date line
        let point1 = Coordinate(latitude: 0, longitude: 179)
        let point2 = Coordinate(latitude: 0, longitude: -179)

        let distance = point1.distance(to: point2)

        // Should be about 2 degrees of longitude at equator = ~120 nm
        XCTAssertEqual(distance, 120, accuracy: 5, "Cross date line distance should work correctly")
    }

    func testNearPolarDistance() {
        // Two points near the north pole
        let point1 = Coordinate(latitude: 89.9, longitude: 0)
        let point2 = Coordinate(latitude: 89.9, longitude: 180)

        let distance = point1.distance(to: point2)

        // Should be a short distance even with 180 degree longitude difference near pole
        XCTAssertLessThan(distance, 20, "Points near pole with large longitude diff should be close")
    }

    // MARK: - CLLocationCoordinate2D Conversion

    func testCLLocationCoordinate2DConversion() {
        let coord = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let clCoord = coord.clLocationCoordinate

        XCTAssertEqual(clCoord.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(clCoord.longitude, -122.4194, accuracy: 0.0001)
    }
}
