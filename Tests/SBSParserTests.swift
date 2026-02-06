import XCTest
@testable import AirJedi

/// Standalone SBS message parser for testing
/// Extracted from SBSProvider to enable unit testing without network connections
struct SBSParser {

    /// Parse a single SBS message line and return an AircraftUpdate if valid
    static func parse(line: String) -> (icaoHex: String, update: SBSUpdate)? {
        let fields = line.components(separatedBy: ",")
        guard fields.count >= 11 else { return nil }
        guard fields[0] == "MSG" else { return nil }

        let icaoHex = fields[4].uppercased()
        guard !icaoHex.isEmpty else { return nil }

        var update = SBSUpdate(icaoHex: icaoHex)

        // Callsign (field 10)
        if fields.count > 10 && !fields[10].isEmpty {
            update.callsign = fields[10].trimmingCharacters(in: .whitespaces)
        }

        // Altitude (field 11)
        if fields.count > 11, let alt = Int(fields[11]) {
            update.altitudeFeet = alt
        }

        // Ground speed (field 12)
        if fields.count > 12, let spd = Double(fields[12]) {
            update.speedKnots = spd
        }

        // Track/heading (field 13)
        if fields.count > 13, let hdg = Double(fields[13]) {
            update.headingDegrees = hdg
        }

        // Latitude (field 14) and Longitude (field 15)
        if fields.count > 15,
           let lat = Double(fields[14]),
           let lon = Double(fields[15]) {
            update.latitude = lat
            update.longitude = lon
        }

        // Vertical rate (field 16)
        if fields.count > 16, let vr = Double(fields[16]) {
            update.verticalRateFpm = vr
        }

        // Squawk (field 17)
        if fields.count > 17 && !fields[17].isEmpty {
            update.squawk = fields[17]
        }

        return (icaoHex, update)
    }

    /// Process a buffer of data, extracting complete lines
    /// Returns array of parsed updates and remaining buffer content
    static func processBuffer(_ buffer: String) -> (updates: [(String, SBSUpdate)], remaining: String) {
        var updates: [(String, SBSUpdate)] = []

        let lines = buffer.components(separatedBy: "\n")
        guard lines.count > 1 else {
            return (updates, buffer)
        }

        // Process all complete lines (all but the last one)
        for i in 0..<(lines.count - 1) {
            var line = lines[i]
            // Remove trailing \r if present (CRLF line endings)
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            if !line.isEmpty, let result = parse(line: line) {
                updates.append(result)
            }
        }

        return (updates, lines.last ?? "")
    }
}

/// Represents parsed SBS message fields
struct SBSUpdate {
    let icaoHex: String
    var callsign: String?
    var altitudeFeet: Int?
    var speedKnots: Double?
    var headingDegrees: Double?
    var latitude: Double?
    var longitude: Double?
    var verticalRateFpm: Double?
    var squawk: String?
}

final class SBSParserTests: XCTestCase {

    // MARK: - Valid MSG Lines

    func testParseCompleteMessage() {
        let line = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,UAL123,35000,450,180,37.7749,-122.4194,-500,1200,0,0,0,0"

        let result = SBSParser.parse(line: line)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.icaoHex, "A12345")
        XCTAssertEqual(result?.update.callsign, "UAL123")
        XCTAssertEqual(result?.update.altitudeFeet, 35000)
        XCTAssertEqual(result?.update.speedKnots, 450)
        XCTAssertEqual(result?.update.headingDegrees, 180)
        XCTAssertEqual(result?.update.latitude ?? 0, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(result?.update.longitude ?? 0, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(result?.update.verticalRateFpm, -500)
        XCTAssertEqual(result?.update.squawk, "1200")
    }

    func testParseMinimalValidMessage() {
        // Minimum valid message: MSG type with ICAO hex (11 fields minimum)
        let line = "MSG,1,1,1,ABC123,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,TEST123"

        let result = SBSParser.parse(line: line)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.icaoHex, "ABC123")
        XCTAssertEqual(result?.update.callsign, "TEST123")
    }

    func testParseMSGType1_Identification() {
        let line = "MSG,1,1,1,A1B2C3,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,SWA1234"

        let result = SBSParser.parse(line: line)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.icaoHex, "A1B2C3")
        XCTAssertEqual(result?.update.callsign, "SWA1234")
    }

    func testParseMSGType3_Position() {
        let line = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,,12000,,,40.7128,-74.0060,,"

        let result = SBSParser.parse(line: line)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.update.altitudeFeet, 12000)
        XCTAssertEqual(result?.update.latitude ?? 0, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(result?.update.longitude ?? 0, -74.0060, accuracy: 0.0001)
        XCTAssertNil(result?.update.callsign) // Empty callsign field
    }

    func testParseMSGType4_Velocity() {
        let line = "MSG,4,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,,,350,270,,,-1000"

        let result = SBSParser.parse(line: line)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.update.speedKnots, 350)
        XCTAssertEqual(result?.update.headingDegrees, 270)
        XCTAssertEqual(result?.update.verticalRateFpm, -1000)
    }

    // MARK: - Missing Optional Fields

    func testParseMessageWithMissingOptionalFields() {
        let line = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,,,,,,"

        let result = SBSParser.parse(line: line)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.icaoHex, "A12345")
        XCTAssertNil(result?.update.callsign)
        XCTAssertNil(result?.update.altitudeFeet)
        XCTAssertNil(result?.update.speedKnots)
        XCTAssertNil(result?.update.headingDegrees)
        XCTAssertNil(result?.update.latitude)
        XCTAssertNil(result?.update.longitude)
        XCTAssertNil(result?.update.verticalRateFpm)
        XCTAssertNil(result?.update.squawk)
    }

    func testParseMessageWithPartialData() {
        // Only altitude and callsign present
        let line = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,UAL123,25000,,,,,"

        let result = SBSParser.parse(line: line)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.update.callsign, "UAL123")
        XCTAssertEqual(result?.update.altitudeFeet, 25000)
        XCTAssertNil(result?.update.speedKnots)
        XCTAssertNil(result?.update.latitude)
    }

    // MARK: - Invalid Lines

    func testRejectNonMSGType() {
        let line = "STA,1,1,1,A12345,1,2024/01/15,12:30:45.000"

        let result = SBSParser.parse(line: line)

        XCTAssertNil(result, "Non-MSG lines should be rejected")
    }

    func testRejectInsufficientFields() {
        let line = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000"  // Only 8 fields

        let result = SBSParser.parse(line: line)

        XCTAssertNil(result, "Lines with fewer than 11 fields should be rejected")
    }

    func testRejectEmptyICAO() {
        let line = "MSG,3,1,1,,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,"

        let result = SBSParser.parse(line: line)

        XCTAssertNil(result, "Lines with empty ICAO hex should be rejected")
    }

    func testRejectEmptyLine() {
        let result = SBSParser.parse(line: "")

        XCTAssertNil(result, "Empty lines should be rejected")
    }

    // MARK: - CRLF vs LF Line Endings

    func testBufferProcessingWithCRLF() {
        let buffer = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,UAL123,35000,,,,,\r\n" +
                     "MSG,3,1,1,B67890,1,2024/01/15,12:30:46.000,2024/01/15,12:30:46.000,DAL456,28000,,,,,\r\n"

        let (updates, remaining) = SBSParser.processBuffer(buffer)

        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].0, "A12345")
        XCTAssertEqual(updates[0].1.callsign, "UAL123")
        XCTAssertEqual(updates[1].0, "B67890")
        XCTAssertEqual(updates[1].1.callsign, "DAL456")
        XCTAssertEqual(remaining, "")
    }

    func testBufferProcessingWithLF() {
        let buffer = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,UAL123,35000,,,,,\n" +
                     "MSG,3,1,1,B67890,1,2024/01/15,12:30:46.000,2024/01/15,12:30:46.000,DAL456,28000,,,,,\n"

        let (updates, remaining) = SBSParser.processBuffer(buffer)

        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].0, "A12345")
        XCTAssertEqual(updates[1].0, "B67890")
        XCTAssertEqual(remaining, "")
    }

    func testBufferProcessingWithMixedLineEndings() {
        let buffer = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,UAL123,35000,,,,,\r\n" +
                     "MSG,3,1,1,B67890,1,2024/01/15,12:30:46.000,2024/01/15,12:30:46.000,DAL456,28000,,,,,\n"

        let (updates, _) = SBSParser.processBuffer(buffer)

        XCTAssertEqual(updates.count, 2, "Mixed line endings should be handled correctly")
    }

    func testBufferRetainsIncompleteMessage() {
        let buffer = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,UAL123,35000,,,,,\n" +
                     "MSG,3,1,1,B67890,1"  // Incomplete message

        let (updates, remaining) = SBSParser.processBuffer(buffer)

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(remaining, "MSG,3,1,1,B67890,1", "Incomplete message should remain in buffer")
    }

    // MARK: - ICAO Hex Normalization

    func testICAOHexUppercased() {
        let line = "MSG,3,1,1,abc123,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,"

        let result = SBSParser.parse(line: line)

        XCTAssertEqual(result?.icaoHex, "ABC123", "ICAO hex should be uppercased")
    }

    // MARK: - Callsign Trimming

    func testCallsignTrimmed() {
        let line = "MSG,1,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,  UAL123  "

        let result = SBSParser.parse(line: line)

        XCTAssertEqual(result?.update.callsign, "UAL123", "Callsign should be trimmed")
    }

    // MARK: - Numeric Parsing

    func testNegativeAltitude() {
        // Below sea level (e.g., Death Valley)
        let line = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,,-200,,,,,"

        let result = SBSParser.parse(line: line)

        XCTAssertEqual(result?.update.altitudeFeet, -200)
    }

    func testNegativeCoordinates() {
        // Southern and Western hemisphere
        let line = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,,10000,,,-33.8688,151.2093,,"

        let result = SBSParser.parse(line: line)

        XCTAssertEqual(result?.update.latitude ?? 0, -33.8688, accuracy: 0.0001)
        XCTAssertEqual(result?.update.longitude ?? 0, 151.2093, accuracy: 0.0001)
    }

    func testNegativeVerticalRate() {
        let line = "MSG,4,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,,,400,90,,,-2000"

        let result = SBSParser.parse(line: line)

        XCTAssertEqual(result?.update.verticalRateFpm, -2000)
    }

    func testDecimalValues() {
        let line = "MSG,3,1,1,A12345,1,2024/01/15,12:30:45.000,2024/01/15,12:30:45.000,,35000,452.5,180.7,37.77490,-122.41940,-500.5"

        let result = SBSParser.parse(line: line)

        XCTAssertEqual(result?.update.speedKnots ?? 0, 452.5, accuracy: 0.1)
        XCTAssertEqual(result?.update.headingDegrees ?? 0, 180.7, accuracy: 0.1)
        XCTAssertEqual(result?.update.verticalRateFpm ?? 0, -500.5, accuracy: 0.1)
    }
}
