import XCTest
@testable import AirJedi

/// Test-friendly AlertEngine wrapper that allows dependency injection
/// This avoids the MainActor and UserDefaults dependencies of the real AlertEngine
final class TestableAlertEngine {
    var alertRules: [AlertRuleConfig] = []
    var cooldownSeconds: TimeInterval = 300
    private var cooldowns: [String: Date] = [:]
    private var previousAircraftState: [String: Aircraft] = [:]
    private var referenceLocation = Coordinate(latitude: 37.7749, longitude: -122.4194)

    init(referenceLocation: Coordinate = Coordinate(latitude: 37.7749, longitude: -122.4194)) {
        self.referenceLocation = referenceLocation
    }

    func evaluate(aircraft: [Aircraft]) -> [TestAlert] {
        let enabledRules = alertRules.filter { $0.isEnabled }
        guard !enabledRules.isEmpty else { return [] }

        var newAlerts: [TestAlert] = []

        for ac in aircraft {
            // Check cooldown
            if let lastAlert = cooldowns[ac.icaoHex],
               Date().timeIntervalSince(lastAlert) < cooldownSeconds {
                continue
            }

            for rule in enabledRules {
                if let alert = evaluateRule(rule, aircraft: ac) {
                    newAlerts.append(alert)
                    cooldowns[ac.icaoHex] = Date()
                    break
                }
            }
        }

        // Update previous state
        for ac in aircraft {
            previousAircraftState[ac.icaoHex] = ac
        }

        return newAlerts
    }

    func clearCooldowns() {
        cooldowns.removeAll()
    }

    func clearPreviousState() {
        previousAircraftState.removeAll()
    }

    private func evaluateRule(_ rule: AlertRuleConfig, aircraft: Aircraft) -> TestAlert? {
        switch rule.type {
        case .proximity:
            return evaluateProximity(rule, aircraft: aircraft)
        case .watchlist:
            return evaluateWatchlist(rule, aircraft: aircraft)
        case .squawk:
            return evaluateSquawk(rule, aircraft: aircraft)
        case .aircraftType:
            return evaluateAircraftType(rule, aircraft: aircraft)
        }
    }

    private func evaluateProximity(_ rule: AlertRuleConfig, aircraft: Aircraft) -> TestAlert? {
        guard let maxDistance = rule.maxDistanceNm,
              let distance = aircraft.distance(from: referenceLocation),
              distance <= maxDistance else {
            return nil
        }

        if let maxAlt = rule.maxAltitudeFeet,
           let alt = aircraft.altitudeFeet,
           alt > maxAlt {
            return nil
        }

        if let minAlt = rule.minAltitudeFeet,
           let alt = aircraft.altitudeFeet,
           alt < minAlt {
            return nil
        }

        // Check if this is a new detection
        if let previous = previousAircraftState[aircraft.icaoHex],
           let prevDistance = previous.distance(from: referenceLocation),
           prevDistance <= maxDistance {
            return nil
        }

        return TestAlert(aircraft: aircraft, ruleId: rule.id, ruleName: rule.name)
    }

    private func evaluateWatchlist(_ rule: AlertRuleConfig, aircraft: Aircraft) -> TestAlert? {
        var matched = false

        if let callsigns = rule.watchCallsigns,
           let callsign = aircraft.callsign,
           callsigns.contains(where: { callsign.uppercased().contains($0.uppercased()) }) {
            matched = true
        }

        if let registrations = rule.watchRegistrations,
           let reg = aircraft.registration,
           registrations.contains(where: { reg.uppercased() == $0.uppercased() }) {
            matched = true
        }

        if let icaos = rule.watchIcaoHex,
           icaos.contains(where: { aircraft.icaoHex.uppercased() == $0.uppercased() }) {
            matched = true
        }

        guard matched else { return nil }

        // Only alert on first detection
        if previousAircraftState[aircraft.icaoHex] != nil {
            return nil
        }

        return TestAlert(aircraft: aircraft, ruleId: rule.id, ruleName: rule.name)
    }

    private func evaluateSquawk(_ rule: AlertRuleConfig, aircraft: Aircraft) -> TestAlert? {
        guard let codes = rule.squawkCodes,
              let squawk = aircraft.squawk,
              codes.contains(squawk) else {
            return nil
        }

        // Check if squawk changed
        if let previous = previousAircraftState[aircraft.icaoHex],
           previous.squawk == squawk {
            return nil
        }

        return TestAlert(aircraft: aircraft, ruleId: rule.id, ruleName: rule.name)
    }

    private func evaluateAircraftType(_ rule: AlertRuleConfig, aircraft: Aircraft) -> TestAlert? {
        guard let typeCodes = rule.typeCodes,
              let typeCode = aircraft.aircraftTypeCode,
              typeCodes.contains(where: { typeCode.uppercased().contains($0.uppercased()) }) else {
            return nil
        }

        // Only alert on first detection
        if previousAircraftState[aircraft.icaoHex] != nil {
            return nil
        }

        return TestAlert(aircraft: aircraft, ruleId: rule.id, ruleName: rule.name)
    }
}

struct TestAlert {
    let aircraft: Aircraft
    let ruleId: UUID
    let ruleName: String
}

final class AlertEngineTests: XCTestCase {

    var engine: TestableAlertEngine!

    override func setUp() {
        super.setUp()
        // San Francisco reference location
        engine = TestableAlertEngine(referenceLocation: Coordinate(latitude: 37.7749, longitude: -122.4194))
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    func makeAircraft(
        icaoHex: String = "A12345",
        callsign: String? = nil,
        position: Coordinate? = nil,
        altitudeFeet: Int? = nil,
        squawk: String? = nil,
        registration: String? = nil,
        aircraftTypeCode: String? = nil
    ) -> Aircraft {
        Aircraft(
            icaoHex: icaoHex,
            callsign: callsign,
            position: position,
            altitudeFeet: altitudeFeet,
            headingDegrees: nil,
            speedKnots: nil,
            verticalRateFpm: nil,
            squawk: squawk,
            lastSeen: Date(),
            registration: registration,
            aircraftTypeCode: aircraftTypeCode,
            operatorName: nil
        )
    }

    // MARK: - Proximity Rule Tests

    func testProximityRuleMatches() {
        var rule = AlertRuleConfig(name: "Nearby", type: .proximity)
        rule.maxDistanceNm = 5.0
        engine.alertRules = [rule]

        // Aircraft 2nm away (approximately 0.033 degrees at this latitude)
        let nearbyPosition = Coordinate(latitude: 37.8049, longitude: -122.4194)
        let aircraft = makeAircraft(position: nearbyPosition, altitudeFeet: 5000)

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.ruleName, "Nearby")
    }

    func testProximityRuleDoesNotMatchFarAircraft() {
        var rule = AlertRuleConfig(name: "Nearby", type: .proximity)
        rule.maxDistanceNm = 5.0
        engine.alertRules = [rule]

        // Aircraft far away (Los Angeles)
        let farPosition = Coordinate(latitude: 33.9425, longitude: -118.4081)
        let aircraft = makeAircraft(position: farPosition, altitudeFeet: 35000)

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertTrue(alerts.isEmpty, "Far aircraft should not trigger proximity alert")
    }

    func testProximityRuleWithMaxAltitude() {
        var rule = AlertRuleConfig(name: "Low and Near", type: .proximity)
        rule.maxDistanceNm = 10.0
        rule.maxAltitudeFeet = 10000
        engine.alertRules = [rule]

        let nearbyPosition = Coordinate(latitude: 37.8049, longitude: -122.4194)

        // Low altitude - should match
        let lowAircraft = makeAircraft(icaoHex: "LOW123", position: nearbyPosition, altitudeFeet: 5000)

        // High altitude - should not match
        let highAircraft = makeAircraft(icaoHex: "HIGH123", position: nearbyPosition, altitudeFeet: 35000)

        let alerts = engine.evaluate(aircraft: [lowAircraft, highAircraft])

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.aircraft.icaoHex, "LOW123")
    }

    func testProximityRuleWithMinAltitude() {
        var rule = AlertRuleConfig(name: "High Only", type: .proximity)
        rule.maxDistanceNm = 10.0
        rule.minAltitudeFeet = 20000
        engine.alertRules = [rule]

        let nearbyPosition = Coordinate(latitude: 37.8049, longitude: -122.4194)

        let lowAircraft = makeAircraft(icaoHex: "LOW123", position: nearbyPosition, altitudeFeet: 5000)
        let highAircraft = makeAircraft(icaoHex: "HIGH123", position: nearbyPosition, altitudeFeet: 35000)

        let alerts = engine.evaluate(aircraft: [lowAircraft, highAircraft])

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.aircraft.icaoHex, "HIGH123")
    }

    func testProximityRuleNoPositionNoMatch() {
        var rule = AlertRuleConfig(name: "Nearby", type: .proximity)
        rule.maxDistanceNm = 5.0
        engine.alertRules = [rule]

        // Aircraft without position
        let aircraft = makeAircraft(position: nil, altitudeFeet: 5000)

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertTrue(alerts.isEmpty, "Aircraft without position should not match proximity rule")
    }

    // MARK: - Watchlist Rule Tests

    func testWatchlistCallsignMatch() {
        var rule = AlertRuleConfig(name: "Watch UAL", type: .watchlist)
        rule.watchCallsigns = ["UAL"]
        engine.alertRules = [rule]

        let aircraft = makeAircraft(callsign: "UAL123")

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1)
    }

    func testWatchlistCallsignPartialMatch() {
        var rule = AlertRuleConfig(name: "Watch SW", type: .watchlist)
        rule.watchCallsigns = ["SWA"]
        engine.alertRules = [rule]

        let aircraft = makeAircraft(callsign: "SWA456")

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1, "Partial callsign match should trigger alert")
    }

    func testWatchlistCallsignCaseInsensitive() {
        var rule = AlertRuleConfig(name: "Watch Delta", type: .watchlist)
        rule.watchCallsigns = ["dal"]  // lowercase
        engine.alertRules = [rule]

        let aircraft = makeAircraft(callsign: "DAL789")  // uppercase

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1, "Callsign matching should be case insensitive")
    }

    func testWatchlistRegistrationMatch() {
        var rule = AlertRuleConfig(name: "Watch N12345", type: .watchlist)
        rule.watchRegistrations = ["N12345"]
        engine.alertRules = [rule]

        let aircraft = makeAircraft(registration: "N12345")

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1)
    }

    func testWatchlistRegistrationExactMatch() {
        var rule = AlertRuleConfig(name: "Watch N12345", type: .watchlist)
        rule.watchRegistrations = ["N12345"]
        engine.alertRules = [rule]

        // Different registration
        let aircraft = makeAircraft(registration: "N12345A")

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertTrue(alerts.isEmpty, "Registration should require exact match")
    }

    func testWatchlistIcaoHexMatch() {
        var rule = AlertRuleConfig(name: "Watch ICAO", type: .watchlist)
        rule.watchIcaoHex = ["ABC123"]
        engine.alertRules = [rule]

        let aircraft = makeAircraft(icaoHex: "ABC123")

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1)
    }

    func testWatchlistIcaoHexCaseInsensitive() {
        var rule = AlertRuleConfig(name: "Watch ICAO", type: .watchlist)
        rule.watchIcaoHex = ["abc123"]  // lowercase
        engine.alertRules = [rule]

        let aircraft = makeAircraft(icaoHex: "ABC123")  // uppercase

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1, "ICAO hex matching should be case insensitive")
    }

    // MARK: - Squawk Rule Tests

    func testSquawkCodeMatch() {
        var rule = AlertRuleConfig(name: "Emergency", type: .squawk)
        rule.squawkCodes = ["7700"]
        engine.alertRules = [rule]

        let aircraft = makeAircraft(squawk: "7700")

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1)
    }

    func testSquawkMultipleCodes() {
        var rule = AlertRuleConfig(name: "All Emergencies", type: .squawk)
        rule.squawkCodes = ["7500", "7600", "7700"]
        engine.alertRules = [rule]

        let hijack = makeAircraft(icaoHex: "A11111", squawk: "7500")
        let radio = makeAircraft(icaoHex: "B22222", squawk: "7600")
        let emergency = makeAircraft(icaoHex: "C33333", squawk: "7700")
        let normal = makeAircraft(icaoHex: "D44444", squawk: "1200")

        let alerts = engine.evaluate(aircraft: [hijack, radio, emergency, normal])

        XCTAssertEqual(alerts.count, 3, "Should match all three emergency squawks")
    }

    func testSquawkNoMatchNormalCode() {
        var rule = AlertRuleConfig(name: "Emergency", type: .squawk)
        rule.squawkCodes = ["7700"]
        engine.alertRules = [rule]

        let aircraft = makeAircraft(squawk: "1200")  // VFR normal

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertTrue(alerts.isEmpty)
    }

    func testSquawkChangeTriggersAlert() {
        var rule = AlertRuleConfig(name: "Emergency", type: .squawk)
        rule.squawkCodes = ["7700"]
        engine.alertRules = [rule]

        // First evaluation with normal squawk
        let normalAircraft = makeAircraft(squawk: "1200")
        _ = engine.evaluate(aircraft: [normalAircraft])

        // Clear cooldowns to allow alert
        engine.clearCooldowns()

        // Second evaluation with emergency squawk
        let emergencyAircraft = makeAircraft(squawk: "7700")
        let alerts = engine.evaluate(aircraft: [emergencyAircraft])

        XCTAssertEqual(alerts.count, 1, "Squawk change should trigger alert")
    }

    func testSquawkNoAlertIfUnchanged() {
        var rule = AlertRuleConfig(name: "Emergency", type: .squawk)
        rule.squawkCodes = ["7700"]
        engine.alertRules = [rule]

        let aircraft = makeAircraft(squawk: "7700")

        // First evaluation
        _ = engine.evaluate(aircraft: [aircraft])

        // Clear cooldowns to allow alert if rule would trigger
        engine.clearCooldowns()

        // Second evaluation - same squawk
        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertTrue(alerts.isEmpty, "Unchanged squawk should not re-alert")
    }

    // MARK: - Aircraft Type Rule Tests

    func testAircraftTypeMatch() {
        var rule = AlertRuleConfig(name: "Military C17", type: .aircraftType)
        rule.typeCodes = ["C17"]
        engine.alertRules = [rule]

        let aircraft = makeAircraft(aircraftTypeCode: "C17")

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1)
    }

    func testAircraftTypePartialMatch() {
        var rule = AlertRuleConfig(name: "Boeing 737s", type: .aircraftType)
        rule.typeCodes = ["B73"]
        engine.alertRules = [rule]

        let b737_800 = makeAircraft(icaoHex: "A11111", aircraftTypeCode: "B738")
        let b737_900 = makeAircraft(icaoHex: "B22222", aircraftTypeCode: "B739")
        let a320 = makeAircraft(icaoHex: "C33333", aircraftTypeCode: "A320")

        let alerts = engine.evaluate(aircraft: [b737_800, b737_900, a320])

        XCTAssertEqual(alerts.count, 2, "Should match both 737 variants")
    }

    func testAircraftTypeCaseInsensitive() {
        var rule = AlertRuleConfig(name: "Test", type: .aircraftType)
        rule.typeCodes = ["b738"]  // lowercase
        engine.alertRules = [rule]

        let aircraft = makeAircraft(aircraftTypeCode: "B738")  // uppercase

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1, "Type code matching should be case insensitive")
    }

    // MARK: - Cooldown Behavior Tests

    func testCooldownPreventsRepeatedAlerts() {
        var rule = AlertRuleConfig(name: "Test", type: .watchlist)
        rule.watchIcaoHex = ["A12345"]
        engine.alertRules = [rule]
        engine.cooldownSeconds = 300

        let aircraft = makeAircraft(icaoHex: "A12345")

        // First evaluation
        let firstAlerts = engine.evaluate(aircraft: [aircraft])
        XCTAssertEqual(firstAlerts.count, 1)

        // Clear previous state but not cooldowns
        engine.clearPreviousState()

        // Second evaluation - should be blocked by cooldown
        let secondAlerts = engine.evaluate(aircraft: [aircraft])
        XCTAssertTrue(secondAlerts.isEmpty, "Cooldown should prevent repeated alerts")
    }

    func testCooldownClearAllowsNewAlerts() {
        var rule = AlertRuleConfig(name: "Test", type: .watchlist)
        rule.watchIcaoHex = ["A12345"]
        engine.alertRules = [rule]
        engine.cooldownSeconds = 300

        let aircraft = makeAircraft(icaoHex: "A12345")

        // First evaluation
        _ = engine.evaluate(aircraft: [aircraft])

        // Clear everything
        engine.clearCooldowns()
        engine.clearPreviousState()

        // Second evaluation - should alert again
        let alerts = engine.evaluate(aircraft: [aircraft])
        XCTAssertEqual(alerts.count, 1, "Cleared cooldown should allow new alerts")
    }

    func testDifferentAircraftNotAffectedByCooldown() {
        var rule = AlertRuleConfig(name: "Test", type: .watchlist)
        rule.watchIcaoHex = ["A12345", "B67890"]
        engine.alertRules = [rule]

        let aircraft1 = makeAircraft(icaoHex: "A12345")
        let aircraft2 = makeAircraft(icaoHex: "B67890")

        // First aircraft triggers
        let firstAlerts = engine.evaluate(aircraft: [aircraft1])
        XCTAssertEqual(firstAlerts.count, 1)

        // Second aircraft should still trigger (different ICAO)
        let secondAlerts = engine.evaluate(aircraft: [aircraft2])
        XCTAssertEqual(secondAlerts.count, 1, "Different aircraft should not share cooldown")
    }

    // MARK: - First Detection Only Tests

    func testWatchlistFirstDetectionOnly() {
        var rule = AlertRuleConfig(name: "Watch", type: .watchlist)
        rule.watchIcaoHex = ["A12345"]
        engine.alertRules = [rule]

        let aircraft = makeAircraft(icaoHex: "A12345")

        // First detection
        let firstAlerts = engine.evaluate(aircraft: [aircraft])
        XCTAssertEqual(firstAlerts.count, 1)

        // Clear cooldown but keep previous state
        engine.clearCooldowns()

        // Still seen - should not re-alert
        let secondAlerts = engine.evaluate(aircraft: [aircraft])
        XCTAssertTrue(secondAlerts.isEmpty, "Watchlist should only alert on first detection")
    }

    func testProximityFirstEntryOnly() {
        var rule = AlertRuleConfig(name: "Nearby", type: .proximity)
        rule.maxDistanceNm = 5.0
        engine.alertRules = [rule]

        let nearbyPosition = Coordinate(latitude: 37.8049, longitude: -122.4194)
        let aircraft = makeAircraft(position: nearbyPosition, altitudeFeet: 5000)

        // First detection within range
        let firstAlerts = engine.evaluate(aircraft: [aircraft])
        XCTAssertEqual(firstAlerts.count, 1)

        // Clear cooldown
        engine.clearCooldowns()

        // Still within range - should not re-alert
        let secondAlerts = engine.evaluate(aircraft: [aircraft])
        XCTAssertTrue(secondAlerts.isEmpty, "Proximity should only alert when first entering range")
    }

    // MARK: - Disabled Rules Tests

    func testDisabledRuleDoesNotTrigger() {
        var rule = AlertRuleConfig(name: "Test", type: .watchlist, isEnabled: false)
        rule.watchIcaoHex = ["A12345"]
        engine.alertRules = [rule]

        let aircraft = makeAircraft(icaoHex: "A12345")

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertTrue(alerts.isEmpty, "Disabled rules should not trigger alerts")
    }

    // MARK: - Multiple Rules Tests

    func testMultipleRulesFirstMatchWins() {
        var rule1 = AlertRuleConfig(name: "Rule1", type: .watchlist)
        rule1.watchIcaoHex = ["A12345"]

        var rule2 = AlertRuleConfig(name: "Rule2", type: .squawk)
        rule2.squawkCodes = ["7700"]

        engine.alertRules = [rule1, rule2]

        // Aircraft matches both rules
        let aircraft = makeAircraft(icaoHex: "A12345", squawk: "7700")

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertEqual(alerts.count, 1, "Only one alert per aircraft per evaluation")
        XCTAssertEqual(alerts.first?.ruleName, "Rule1", "First matching rule should win")
    }

    func testNoRulesNoAlerts() {
        engine.alertRules = []

        let aircraft = makeAircraft(squawk: "7700")

        let alerts = engine.evaluate(aircraft: [aircraft])

        XCTAssertTrue(alerts.isEmpty, "No rules should mean no alerts")
    }
}
