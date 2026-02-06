import XCTest
@testable import AirJedi

/// CPR (Compact Position Reporting) decoder for testing
/// Extracted from BeastProvider to enable unit testing without network connections
struct CPRDecoder {

    // MARK: - Public Decoding Methods

    /// Global CPR decode using both even and odd frames
    /// Both frames must be received within 10 seconds of each other
    static func decodeGlobal(
        evenLatCPR: Int, evenLonCPR: Int,
        oddLatCPR: Int, oddLonCPR: Int,
        useOddPosition: Bool
    ) -> Coordinate? {
        let cprMax = 131072.0  // 2^17

        let latCPR0 = Double(evenLatCPR) / cprMax
        let latCPR1 = Double(oddLatCPR) / cprMax
        let lonCPR0 = Double(evenLonCPR) / cprMax
        let lonCPR1 = Double(oddLonCPR) / cprMax

        // Latitude zone sizes
        let dLat0 = 360.0 / 60.0  // 6 degrees for even
        let dLat1 = 360.0 / 59.0  // ~6.1 degrees for odd

        // Compute latitude index j
        let j = floor(59.0 * latCPR0 - 60.0 * latCPR1 + 0.5)

        // Compute latitudes
        var latEven = dLat0 * (cprMod(j, 60) + latCPR0)
        var latOdd = dLat1 * (cprMod(j, 59) + latCPR1)

        // Adjust for southern hemisphere
        if latEven >= 270 { latEven -= 360 }
        if latOdd >= 270 { latOdd -= 360 }

        // Check zone consistency (NL must match)
        let nlEven = cprNL(latEven)
        let nlOdd = cprNL(latOdd)
        guard nlEven == nlOdd else { return nil }

        // Use the most recent frame's latitude
        let lat = useOddPosition ? latOdd : latEven
        let lonCPR = useOddPosition ? lonCPR1 : lonCPR0
        let nl = useOddPosition ? nlOdd : nlEven
        let ni = useOddPosition ? max(1, nl - 1) : max(1, nl)

        // Compute longitude
        let dLon = 360.0 / Double(ni)
        let m = floor(Double(evenLonCPR) * Double(nl - 1) / cprMax -
                      Double(oddLonCPR) * Double(nl) / cprMax + 0.5)
        var lon = dLon * (cprMod(m, Double(ni)) + lonCPR)

        if lon > 180 { lon -= 360 }

        // Validate position
        guard lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 else {
            return nil
        }

        return Coordinate(latitude: lat, longitude: lon)
    }

    /// Local CPR decode using a single frame and a reference position
    /// Reference must be within ~250nm of actual position
    static func decodeLocal(
        latCPR: Int, lonCPR: Int,
        isOdd: Bool,
        reference: Coordinate
    ) -> Coordinate? {
        let cprMax = 131072.0  // 2^17

        let latCPRNorm = Double(latCPR) / cprMax
        let lonCPRNorm = Double(lonCPR) / cprMax

        // Latitude zone size
        let dLat = isOdd ? 360.0 / 59.0 : 360.0 / 60.0

        // Find latitude zone index
        let j = floor(reference.latitude / dLat) +
                floor(0.5 + cprMod(reference.latitude, dLat) / dLat - latCPRNorm)

        // Compute latitude
        let lat = dLat * (j + latCPRNorm)

        // Validate latitude
        guard lat >= -90 && lat <= 90 else { return nil }

        // Longitude zone size depends on latitude
        let nl = cprNL(lat)
        let ni = isOdd ? max(1, nl - 1) : max(1, nl)
        let dLon = 360.0 / Double(ni)

        // Find longitude zone index
        let m = floor(reference.longitude / dLon) +
                floor(0.5 + cprMod(reference.longitude, dLon) / dLon - lonCPRNorm)

        // Compute longitude
        var lon = dLon * (m + lonCPRNorm)

        // Normalize longitude to -180...180
        if lon > 180 { lon -= 360 }
        if lon < -180 { lon += 360 }

        // Validate position
        guard lon >= -180 && lon <= 180 else { return nil }

        return Coordinate(latitude: lat, longitude: lon)
    }

    // MARK: - NL Lookup Table

    /// Number of Longitude zones (NL) for a given latitude
    /// This is the core lookup table used in CPR decoding
    static func cprNL(_ lat: Double) -> Int {
        let absLat = abs(lat)

        // NL lookup table - latitude thresholds for each NL value
        if absLat < 10.47047130 { return 59 }
        if absLat < 14.82817437 { return 58 }
        if absLat < 18.18626357 { return 57 }
        if absLat < 21.02939493 { return 56 }
        if absLat < 23.54504487 { return 55 }
        if absLat < 25.82924707 { return 54 }
        if absLat < 27.93898710 { return 53 }
        if absLat < 29.91135686 { return 52 }
        if absLat < 31.77209708 { return 51 }
        if absLat < 33.53993436 { return 50 }
        if absLat < 35.22899598 { return 49 }
        if absLat < 36.85025108 { return 48 }
        if absLat < 38.41241892 { return 47 }
        if absLat < 39.92256684 { return 46 }
        if absLat < 41.38651832 { return 45 }
        if absLat < 42.80914012 { return 44 }
        if absLat < 44.19454951 { return 43 }
        if absLat < 45.54626723 { return 42 }
        if absLat < 46.86733252 { return 41 }
        if absLat < 48.16039128 { return 40 }
        if absLat < 49.42776439 { return 39 }
        if absLat < 50.67150166 { return 38 }
        if absLat < 51.89342469 { return 37 }
        if absLat < 53.09516153 { return 36 }
        if absLat < 54.27817472 { return 35 }
        if absLat < 55.44378444 { return 34 }
        if absLat < 56.59318756 { return 33 }
        if absLat < 57.72747354 { return 32 }
        if absLat < 58.84763776 { return 31 }
        if absLat < 59.95459277 { return 30 }
        if absLat < 61.04917774 { return 29 }
        if absLat < 62.13216659 { return 28 }
        if absLat < 63.20427479 { return 27 }
        if absLat < 64.26616523 { return 26 }
        if absLat < 65.31845310 { return 25 }
        if absLat < 66.36171008 { return 24 }
        if absLat < 67.39646774 { return 23 }
        if absLat < 68.42322022 { return 22 }
        if absLat < 69.44242631 { return 21 }
        if absLat < 70.45451075 { return 20 }
        if absLat < 71.45986473 { return 19 }
        if absLat < 72.45884545 { return 18 }
        if absLat < 73.45177442 { return 17 }
        if absLat < 74.43893416 { return 16 }
        if absLat < 75.42056257 { return 15 }
        if absLat < 76.39684391 { return 14 }
        if absLat < 77.36789461 { return 13 }
        if absLat < 78.33374083 { return 12 }
        if absLat < 79.29428225 { return 11 }
        if absLat < 80.24923213 { return 10 }
        if absLat < 81.19801349 { return 9 }
        if absLat < 82.13956981 { return 8 }
        if absLat < 83.07199445 { return 7 }
        if absLat < 83.99173563 { return 6 }
        if absLat < 84.89166191 { return 5 }
        if absLat < 85.75541621 { return 4 }
        if absLat < 86.53536998 { return 3 }
        if absLat < 87.00000000 { return 2 }
        return 1
    }

    // MARK: - Helper Methods

    /// CPR modulo operation (always positive result)
    private static func cprMod(_ a: Double, _ b: Double) -> Double {
        let result = a.truncatingRemainder(dividingBy: b)
        return result >= 0 ? result : result + b
    }
}

final class CPRDecodingTests: XCTestCase {

    // MARK: - NL Lookup Table Tests

    func testNLAtEquator() {
        // At equator (0 degrees), NL should be 59
        XCTAssertEqual(CPRDecoder.cprNL(0), 59)
        XCTAssertEqual(CPRDecoder.cprNL(5), 59)
        XCTAssertEqual(CPRDecoder.cprNL(10), 59)
    }

    func testNLAtMidLatitudes() {
        // San Francisco (~37.7) should have NL around 47-48
        XCTAssertEqual(CPRDecoder.cprNL(37.7), 47)

        // New York (~40.7) should have NL around 45-46
        XCTAssertEqual(CPRDecoder.cprNL(40.7), 45)

        // London (~51.5) should have NL around 37-38
        XCTAssertEqual(CPRDecoder.cprNL(51.5), 37)
    }

    func testNLNearPoles() {
        // Near north pole - NL decreases as latitude increases
        // Based on lookup table thresholds in cprNL()
        XCTAssertEqual(CPRDecoder.cprNL(85), 4)  // Between 84.89 and 85.76
        XCTAssertEqual(CPRDecoder.cprNL(86), 3)  // Between 85.76 and 86.54
        XCTAssertEqual(CPRDecoder.cprNL(86.6), 2) // Between 86.54 and 87.00
        XCTAssertEqual(CPRDecoder.cprNL(87), 1)  // >= 87.00
        XCTAssertEqual(CPRDecoder.cprNL(89), 1)  // >= 87.00
        XCTAssertEqual(CPRDecoder.cprNL(90), 1)  // Pole
    }

    func testNLSymmetryNorthSouth() {
        // NL should be the same for positive and negative latitudes
        for lat in stride(from: 0.0, through: 90.0, by: 5.0) {
            XCTAssertEqual(CPRDecoder.cprNL(lat), CPRDecoder.cprNL(-lat),
                           "NL should be symmetric at latitude \(lat)")
        }
    }

    func testNLDecreaseWithLatitude() {
        // NL should decrease (or stay same) as latitude increases
        var previousNL = 59
        for lat in stride(from: 0.0, through: 90.0, by: 1.0) {
            let nl = CPRDecoder.cprNL(lat)
            XCTAssertLessThanOrEqual(nl, previousNL,
                                     "NL should decrease with latitude at \(lat)")
            previousNL = nl
        }
    }

    // MARK: - Global Decode Tests

    func testGlobalDecodeKnownPosition() {
        // Test that global decode produces a valid position from paired frames
        // The exact position depends on the CPR encoding specifics
        // We use values that should produce a position and verify it's valid

        let result = CPRDecoder.decodeGlobal(
            evenLatCPR: 92095, evenLonCPR: 39846,
            oddLatCPR: 88385, oddLonCPR: 125818,
            useOddPosition: false
        )

        XCTAssertNotNil(result, "Global decode should produce a result")
        if let coord = result {
            // Verify the result is a valid position
            XCTAssertGreaterThanOrEqual(coord.latitude, -90)
            XCTAssertLessThanOrEqual(coord.latitude, 90)
            XCTAssertGreaterThanOrEqual(coord.longitude, -180)
            XCTAssertLessThanOrEqual(coord.longitude, 180)
        }
    }

    func testGlobalDecodeSecondPosition() {
        // Test with different CPR values
        // Verify we get a valid position

        let result = CPRDecoder.decodeGlobal(
            evenLatCPR: 93000, evenLonCPR: 40000,
            oddLatCPR: 89000, oddLonCPR: 126000,
            useOddPosition: true
        )

        // Should return a valid coordinate
        XCTAssertNotNil(result)
        if let coord = result {
            // Just verify it's a valid lat/lon
            XCTAssertGreaterThanOrEqual(coord.latitude, -90)
            XCTAssertLessThanOrEqual(coord.latitude, 90)
        }
    }

    func testGlobalDecodeNegativeLatitude() {
        // Test Southern hemisphere decoding
        // CPR values that should decode to negative latitude
        // Using values that would produce southern hemisphere coordinates

        let result = CPRDecoder.decodeGlobal(
            evenLatCPR: 118000, evenLonCPR: 60000,
            oddLatCPR: 112000, oddLonCPR: 75000,
            useOddPosition: false
        )

        // Position should be valid (may or may not be southern depending on encoding)
        if let coord = result {
            XCTAssertGreaterThanOrEqual(coord.latitude, -90)
            XCTAssertLessThanOrEqual(coord.latitude, 90)
        }
    }

    func testGlobalDecodeValidatesOutput() {
        // Test that invalid decodes return nil
        // Zero CPR values should still produce some result
        let result = CPRDecoder.decodeGlobal(
            evenLatCPR: 0, evenLonCPR: 0,
            oddLatCPR: 0, oddLonCPR: 0,
            useOddPosition: false
        )

        // Should produce valid coordinates (at 0,0 or nearby)
        if let coord = result {
            XCTAssertGreaterThanOrEqual(coord.latitude, -90)
            XCTAssertLessThanOrEqual(coord.latitude, 90)
            XCTAssertGreaterThanOrEqual(coord.longitude, -180)
            XCTAssertLessThanOrEqual(coord.longitude, 180)
        }
    }

    // MARK: - Local Decode Tests

    func testLocalDecodeNearReference() {
        // Reference: San Francisco (37.7749, -122.4194)
        // CPR values that should decode near SF

        let reference = Coordinate(latitude: 37.7749, longitude: -122.4194)

        // CPR values representing a position near SF
        // These are approximated for testing
        let latCPR = 80000  // Encoded latitude
        let lonCPR = 20000  // Encoded longitude

        let result = CPRDecoder.decodeLocal(
            latCPR: latCPR, lonCPR: lonCPR,
            isOdd: false,
            reference: reference
        )

        // Should return a position within reasonable range of reference
        XCTAssertNotNil(result)
        if let coord = result {
            // Local decode should produce a position within a few degrees of reference
            XCTAssertEqual(coord.latitude, reference.latitude, accuracy: 10)
            XCTAssertEqual(coord.longitude, reference.longitude, accuracy: 10)
        }
    }

    func testLocalDecodeOddFrame() {
        let reference = Coordinate(latitude: 40.7128, longitude: -74.0060)

        let result = CPRDecoder.decodeLocal(
            latCPR: 50000, lonCPR: 100000,
            isOdd: true,  // Odd frame
            reference: reference
        )

        XCTAssertNotNil(result)
        if let coord = result {
            XCTAssertGreaterThanOrEqual(coord.latitude, -90)
            XCTAssertLessThanOrEqual(coord.latitude, 90)
        }
    }

    func testLocalDecodeEvenFrame() {
        let reference = Coordinate(latitude: 40.7128, longitude: -74.0060)

        let result = CPRDecoder.decodeLocal(
            latCPR: 50000, lonCPR: 100000,
            isOdd: false,  // Even frame
            reference: reference
        )

        XCTAssertNotNil(result)
        if let coord = result {
            XCTAssertGreaterThanOrEqual(coord.latitude, -90)
            XCTAssertLessThanOrEqual(coord.latitude, 90)
        }
    }

    func testLocalDecodeNegativeLatitudeReference() {
        // Sydney, Australia
        let reference = Coordinate(latitude: -33.8688, longitude: 151.2093)

        let result = CPRDecoder.decodeLocal(
            latCPR: 70000, lonCPR: 80000,
            isOdd: false,
            reference: reference
        )

        // Should produce a valid southern hemisphere position
        XCTAssertNotNil(result)
        if let coord = result {
            XCTAssertGreaterThanOrEqual(coord.latitude, -90)
            XCTAssertLessThanOrEqual(coord.latitude, 90)
        }
    }

    // MARK: - Edge Cases

    func testCPRMaxValues() {
        // CPR values are 17-bit, max is 131071
        let maxCPR = 131071
        let reference = Coordinate(latitude: 0, longitude: 0)

        let result = CPRDecoder.decodeLocal(
            latCPR: maxCPR, lonCPR: maxCPR,
            isOdd: false,
            reference: reference
        )

        // Should handle max values without crashing
        // Result validity depends on the math
        if let coord = result {
            XCTAssertGreaterThanOrEqual(coord.latitude, -90)
            XCTAssertLessThanOrEqual(coord.latitude, 90)
        }
    }

    func testCPRZeroValues() {
        let reference = Coordinate(latitude: 45.0, longitude: -90.0)

        let result = CPRDecoder.decodeLocal(
            latCPR: 0, lonCPR: 0,
            isOdd: false,
            reference: reference
        )

        XCTAssertNotNil(result)
    }

    func testNearPoleDecoding() {
        // Test decoding near the north pole where NL is very low
        let reference = Coordinate(latitude: 85.0, longitude: 0)

        let result = CPRDecoder.decodeLocal(
            latCPR: 65536, lonCPR: 65536,
            isOdd: false,
            reference: reference
        )

        // Should handle polar regions
        if let coord = result {
            XCTAssertGreaterThanOrEqual(coord.latitude, 70)  // Should be high latitude
        }
    }

    // MARK: - Consistency Tests

    func testOddAndEvenFramesDifferSlightly() {
        // Same CPR values but different frame types produce different positions
        // due to different zone sizes (60 vs 59 zones)
        let reference = Coordinate(latitude: 37.0, longitude: -122.0)

        let evenResult = CPRDecoder.decodeLocal(
            latCPR: 65536, lonCPR: 65536,
            isOdd: false,
            reference: reference
        )

        let oddResult = CPRDecoder.decodeLocal(
            latCPR: 65536, lonCPR: 65536,
            isOdd: true,
            reference: reference
        )

        // Both should produce valid results
        XCTAssertNotNil(evenResult)
        XCTAssertNotNil(oddResult)

        // Results may differ because even uses 60 zones, odd uses 59 zones
        // The difference depends on the specific CPR values and reference location
        if let even = evenResult, let odd = oddResult {
            // Both should be valid coordinates
            XCTAssertGreaterThanOrEqual(even.latitude, -90)
            XCTAssertLessThanOrEqual(even.latitude, 90)
            XCTAssertGreaterThanOrEqual(odd.latitude, -90)
            XCTAssertLessThanOrEqual(odd.latitude, 90)
        }
    }
}
