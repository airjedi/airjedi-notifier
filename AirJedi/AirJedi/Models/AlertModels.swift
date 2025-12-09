import Foundation

// MARK: - Alert Priority

enum AlertPriority: String, Codable, CaseIterable, Identifiable {
    case low
    case normal
    case high
    case critical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Alert Sound

enum AlertSound: String, Codable, CaseIterable, Identifiable {
    case none
    case subtle
    case standard
    case prominent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .subtle: return "Subtle"
        case .standard: return "Standard"
        case .prominent: return "Prominent"
        }
    }

    var systemSoundName: String? {
        switch self {
        case .none: return nil
        case .subtle: return "Pop"
        case .standard: return "Glass"
        case .prominent: return "Hero"
        }
    }
}

// MARK: - Alert

struct Alert: Identifiable {
    let id: UUID
    let aircraft: Aircraft
    let ruleId: UUID
    let ruleName: String
    let title: String
    let body: String
    let priority: AlertPriority
    let sound: AlertSound
    let timestamp: Date

    init(
        aircraft: Aircraft,
        ruleId: UUID,
        ruleName: String,
        title: String,
        body: String,
        priority: AlertPriority,
        sound: AlertSound
    ) {
        self.id = UUID()
        self.aircraft = aircraft
        self.ruleId = ruleId
        self.ruleName = ruleName
        self.title = title
        self.body = body
        self.priority = priority
        self.sound = sound
        self.timestamp = Date()
    }
}

// MARK: - Alert Rule Type

enum AlertRuleType: String, Codable, CaseIterable, Identifiable {
    case proximity
    case watchlist
    case squawk
    case aircraftType

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .proximity: return "Proximity"
        case .watchlist: return "Watchlist"
        case .squawk: return "Emergency Squawk"
        case .aircraftType: return "Aircraft Type"
        }
    }

    var icon: String {
        switch self {
        case .proximity: return "location.circle"
        case .watchlist: return "star.circle"
        case .squawk: return "exclamationmark.triangle"
        case .aircraftType: return "airplane.circle"
        }
    }
}

// MARK: - Alert Rule (Codable wrapper)

struct AlertRuleConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: AlertRuleType
    var isEnabled: Bool
    var priority: AlertPriority
    var sound: AlertSound

    // Proximity settings
    var maxDistanceNm: Double?
    var maxAltitudeFeet: Int?
    var minAltitudeFeet: Int?

    // Watchlist settings
    var watchCallsigns: [String]?
    var watchRegistrations: [String]?
    var watchIcaoHex: [String]?

    // Squawk settings
    var squawkCodes: [String]?

    // Aircraft type settings
    var typeCategories: [String]?  // "military", "helicopter", etc.
    var typeCodes: [String]?  // "C17", "F16", etc.

    init(
        id: UUID = UUID(),
        name: String,
        type: AlertRuleType,
        isEnabled: Bool = true,
        priority: AlertPriority = .normal,
        sound: AlertSound = .standard
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isEnabled = isEnabled
        self.priority = priority
        self.sound = sound
    }

    static func defaultProximityRule() -> AlertRuleConfig {
        var rule = AlertRuleConfig(name: "Nearby Aircraft", type: .proximity)
        rule.maxDistanceNm = 5.0
        rule.maxAltitudeFeet = 10000
        return rule
    }

    static func defaultSquawkRule() -> AlertRuleConfig {
        var rule = AlertRuleConfig(name: "Emergency Squawks", type: .squawk, priority: .critical, sound: .prominent)
        rule.squawkCodes = ["7500", "7600", "7700"]
        return rule
    }
}
