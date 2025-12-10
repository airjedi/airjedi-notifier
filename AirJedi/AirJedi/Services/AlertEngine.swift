import Foundation
import Combine

@MainActor
class AlertEngine: ObservableObject {
    @Published private(set) var recentAlerts: [Alert] = []
    @Published var alertRules: [AlertRuleConfig] = []

    private let settings = SettingsManager.shared
    private var cooldowns: [String: Date] = [:]  // icaoHex -> lastAlerted
    private var previousAircraftState: [String: Aircraft] = [:]

    var cooldownSeconds: TimeInterval = 300  // 5 minutes

    init() {
        loadRules()
    }

    // MARK: - Rule Management

    func loadRules() {
        if let data = UserDefaults.standard.data(forKey: "alertRules"),
           let rules = try? JSONDecoder().decode([AlertRuleConfig].self, from: data) {
            alertRules = rules
        }
    }

    func saveRules() {
        if let data = try? JSONEncoder().encode(alertRules) {
            UserDefaults.standard.set(data, forKey: "alertRules")
        }
    }

    func addRule(_ rule: AlertRuleConfig) {
        alertRules.append(rule)
        saveRules()
    }

    func updateRule(_ rule: AlertRuleConfig) {
        if let index = alertRules.firstIndex(where: { $0.id == rule.id }) {
            alertRules[index] = rule
            saveRules()
        }
    }

    func deleteRule(id: UUID) {
        alertRules.removeAll { $0.id == id }
        saveRules()
    }

    // MARK: - Evaluation

    func evaluate(aircraft: [Aircraft]) -> [Alert] {
        let enabledRules = alertRules.filter { $0.isEnabled }
        guard !enabledRules.isEmpty else { return [] }

        var newAlerts: [Alert] = []
        let referenceLocation = settings.referenceLocation

        for ac in aircraft {
            // Check cooldown
            if let lastAlert = cooldowns[ac.icaoHex],
               Date().timeIntervalSince(lastAlert) < cooldownSeconds {
                continue
            }

            for rule in enabledRules {
                if let alert = evaluateRule(rule, aircraft: ac, referenceLocation: referenceLocation) {
                    newAlerts.append(alert)
                    cooldowns[ac.icaoHex] = Date()
                    break  // One alert per aircraft per evaluation
                }
            }
        }

        // Update previous state
        for ac in aircraft {
            previousAircraftState[ac.icaoHex] = ac
        }

        // Add to recent alerts (keep last 50)
        recentAlerts.insert(contentsOf: newAlerts, at: 0)
        if recentAlerts.count > 50 {
            recentAlerts = Array(recentAlerts.prefix(50))
        }

        return newAlerts
    }

    private func evaluateRule(_ rule: AlertRuleConfig, aircraft: Aircraft, referenceLocation: Coordinate) -> Alert? {
        switch rule.type {
        case .proximity:
            return evaluateProximity(rule, aircraft: aircraft, referenceLocation: referenceLocation)
        case .watchlist:
            return evaluateWatchlist(rule, aircraft: aircraft)
        case .squawk:
            return evaluateSquawk(rule, aircraft: aircraft)
        case .aircraftType:
            return evaluateAircraftType(rule, aircraft: aircraft)
        }
    }

    // MARK: - Rule Evaluators

    private func evaluateProximity(_ rule: AlertRuleConfig, aircraft: Aircraft, referenceLocation: Coordinate) -> Alert? {
        guard let maxDistance = rule.maxDistanceNm,
              let distance = aircraft.distance(from: referenceLocation),
              distance <= maxDistance else {
            return nil
        }

        // Check altitude bounds if specified
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

        // Check if this is a new detection (wasn't within range before)
        if let previous = previousAircraftState[aircraft.icaoHex],
           let prevDistance = previous.distance(from: referenceLocation),
           prevDistance <= maxDistance {
            return nil  // Already was in range
        }

        let callsign = aircraft.callsign ?? aircraft.icaoHex
        let detailBody = aircraft.detailSummary(referenceLocation: settings.referenceLocation)

        return Alert(
            aircraft: aircraft,
            ruleId: rule.id,
            ruleName: rule.name,
            title: "Aircraft Nearby: \(callsign)",
            subtitle: aircraft.notificationSubtitle,
            body: detailBody,
            priority: rule.priority,
            sound: rule.sound,
            sendNotification: rule.sendNotification
        )
    }

    private func evaluateWatchlist(_ rule: AlertRuleConfig, aircraft: Aircraft) -> Alert? {
        var matched = false
        var matchReason = ""

        if let callsigns = rule.watchCallsigns,
           let callsign = aircraft.callsign,
           callsigns.contains(where: { callsign.uppercased().contains($0.uppercased()) }) {
            matched = true
            matchReason = "Callsign match: \(callsign)"
        }

        if let registrations = rule.watchRegistrations,
           let reg = aircraft.registration,
           registrations.contains(where: { reg.uppercased() == $0.uppercased() }) {
            matched = true
            matchReason = "Registration match: \(reg)"
        }

        if let icaos = rule.watchIcaoHex,
           icaos.contains(where: { aircraft.icaoHex.uppercased() == $0.uppercased() }) {
            matched = true
            matchReason = "ICAO match: \(aircraft.icaoHex)"
        }

        guard matched else { return nil }

        // Only alert on first detection
        if previousAircraftState[aircraft.icaoHex] != nil {
            return nil
        }

        let callsign = aircraft.callsign ?? aircraft.icaoHex
        let detailBody = "\(matchReason)\n" + aircraft.detailSummary(referenceLocation: settings.referenceLocation)

        return Alert(
            aircraft: aircraft,
            ruleId: rule.id,
            ruleName: rule.name,
            title: "Watchlist: \(callsign)",
            subtitle: aircraft.notificationSubtitle,
            body: detailBody,
            priority: rule.priority,
            sound: rule.sound,
            sendNotification: rule.sendNotification
        )
    }

    private func evaluateSquawk(_ rule: AlertRuleConfig, aircraft: Aircraft) -> Alert? {
        guard let codes = rule.squawkCodes,
              let squawk = aircraft.squawk,
              codes.contains(squawk) else {
            return nil
        }

        // Check if squawk changed (new emergency)
        if let previous = previousAircraftState[aircraft.icaoHex],
           previous.squawk == squawk {
            return nil
        }

        let callsign = aircraft.callsign ?? aircraft.icaoHex
        let squawkMeaning: String
        switch squawk {
        case "7500": squawkMeaning = "HIJACK"
        case "7600": squawkMeaning = "RADIO FAILURE"
        case "7700": squawkMeaning = "EMERGENCY"
        default: squawkMeaning = "Code \(squawk)"
        }
        let detailBody = aircraft.detailSummary(referenceLocation: settings.referenceLocation)

        return Alert(
            aircraft: aircraft,
            ruleId: rule.id,
            ruleName: rule.name,
            title: "⚠️ \(squawkMeaning): \(callsign)",
            subtitle: aircraft.notificationSubtitle,
            body: detailBody,
            priority: rule.priority,
            sound: rule.sound,
            sendNotification: rule.sendNotification
        )
    }

    private func evaluateAircraftType(_ rule: AlertRuleConfig, aircraft: Aircraft) -> Alert? {
        var matched = false

        if let typeCodes = rule.typeCodes,
           let typeCode = aircraft.aircraftTypeCode,
           typeCodes.contains(where: { typeCode.uppercased().contains($0.uppercased()) }) {
            matched = true
        }

        // For categories, we'd need enrichment data - skip for now
        // if let categories = rule.typeCategories { ... }

        guard matched else { return nil }

        // Only alert on first detection
        if previousAircraftState[aircraft.icaoHex] != nil {
            return nil
        }

        let callsign = aircraft.callsign ?? aircraft.icaoHex
        let typeCode = aircraft.aircraftTypeCode ?? "Unknown"
        let detailBody = aircraft.detailSummary(referenceLocation: settings.referenceLocation)

        return Alert(
            aircraft: aircraft,
            ruleId: rule.id,
            ruleName: rule.name,
            title: "\(typeCode): \(callsign)",
            subtitle: aircraft.notificationSubtitle,
            body: detailBody,
            priority: rule.priority,
            sound: rule.sound,
            sendNotification: rule.sendNotification
        )
    }

    // MARK: - Cooldown Management

    func clearCooldowns() {
        cooldowns.removeAll()
    }

    func clearAlerts() {
        recentAlerts.removeAll()
    }
}
