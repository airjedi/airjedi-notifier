import Foundation

enum SourceType: String, Codable, CaseIterable, Identifiable {
    case dump1090 = "dump1090"
    case beast = "beast"
    case sbs = "sbs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dump1090: return "dump1090 / readsb"
        case .beast: return "Beast (AVR)"
        case .sbs: return "SBS BaseStation"
        }
    }

    var defaultPort: Int {
        switch self {
        case .dump1090: return 8080
        case .beast: return 30005
        case .sbs: return 30003
        }
    }

    var protocolDescription: String {
        switch self {
        case .dump1090: return "HTTP JSON"
        case .beast: return "TCP Binary"
        case .sbs: return "TCP Text"
        }
    }
}

struct SourceConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: SourceType
    var host: String
    var port: Int
    var isEnabled: Bool
    var priority: Int

    init(
        id: UUID = UUID(),
        name: String = "New Source",
        type: SourceType = .dump1090,
        host: String = "localhost",
        port: Int? = nil,
        isEnabled: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host
        self.port = port ?? type.defaultPort
        self.isEnabled = isEnabled
        self.priority = priority
    }

    var urlString: String {
        switch type {
        case .dump1090:
            return "http://\(host):\(port)/data/aircraft.json"
        case .beast, .sbs:
            return "\(host):\(port)"
        }
    }
}
