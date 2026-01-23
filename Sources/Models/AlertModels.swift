import Foundation
import SwiftUI

// MARK: - Alert Color (Codable wrapper for SwiftUI Color)

struct AlertColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        // Convert Color to NSColor to extract components
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.white
        self.red = Double(nsColor.redComponent)
        self.green = Double(nsColor.greenComponent)
        self.blue = Double(nsColor.blueComponent)
        self.alpha = Double(nsColor.alphaComponent)
    }

    static let defaultHighlight = AlertColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0) // Orange
}

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
    let subtitle: String?
    let body: String
    let priority: AlertPriority
    let sound: AlertSound
    let sendNotification: Bool
    let timestamp: Date

    init(
        aircraft: Aircraft,
        ruleId: UUID,
        ruleName: String,
        title: String,
        subtitle: String? = nil,
        body: String,
        priority: AlertPriority,
        sound: AlertSound,
        sendNotification: Bool = true
    ) {
        self.id = UUID()
        self.aircraft = aircraft
        self.ruleId = ruleId
        self.ruleName = ruleName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.priority = priority
        self.sound = sound
        self.sendNotification = sendNotification
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
    var sendNotification: Bool

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

    // Highlight settings
    var highlightColor: AlertColor?  // nil = no highlighting

    init(
        id: UUID = UUID(),
        name: String,
        type: AlertRuleType,
        isEnabled: Bool = true,
        priority: AlertPriority = .normal,
        sound: AlertSound = .standard,
        sendNotification: Bool = true
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isEnabled = isEnabled
        self.priority = priority
        self.sound = sound
        self.sendNotification = sendNotification
    }

    // Custom decoder to handle missing sendNotification key for existing saved rules
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(AlertRuleType.self, forKey: .type)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        priority = try container.decode(AlertPriority.self, forKey: .priority)
        sound = try container.decode(AlertSound.self, forKey: .sound)
        sendNotification = try container.decodeIfPresent(Bool.self, forKey: .sendNotification) ?? true
        maxDistanceNm = try container.decodeIfPresent(Double.self, forKey: .maxDistanceNm)
        maxAltitudeFeet = try container.decodeIfPresent(Int.self, forKey: .maxAltitudeFeet)
        minAltitudeFeet = try container.decodeIfPresent(Int.self, forKey: .minAltitudeFeet)
        watchCallsigns = try container.decodeIfPresent([String].self, forKey: .watchCallsigns)
        watchRegistrations = try container.decodeIfPresent([String].self, forKey: .watchRegistrations)
        watchIcaoHex = try container.decodeIfPresent([String].self, forKey: .watchIcaoHex)
        squawkCodes = try container.decodeIfPresent([String].self, forKey: .squawkCodes)
        typeCategories = try container.decodeIfPresent([String].self, forKey: .typeCategories)
        typeCodes = try container.decodeIfPresent([String].self, forKey: .typeCodes)
        highlightColor = try container.decodeIfPresent(AlertColor.self, forKey: .highlightColor)
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
