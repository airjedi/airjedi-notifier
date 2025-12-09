import Foundation
import Combine

// MARK: - Provider Status

enum ProviderStatus: Equatable {
    case disconnected
    case connecting
    case connected(aircraftCount: Int)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected(let count): return "Connected (\(count) aircraft)"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Aircraft Update

enum AircraftUpdate {
    case updated(Aircraft)
    case removed(String)  // icaoHex of aircraft to remove
    case snapshot([Aircraft])  // Full state replacement
}

// MARK: - Provider Protocol

protocol ADSBProvider: AnyObject, Identifiable {
    var id: UUID { get }
    var config: SourceConfig { get }
    var status: ProviderStatus { get }
    var statusPublisher: AnyPublisher<ProviderStatus, Never> { get }
    var aircraftPublisher: AnyPublisher<AircraftUpdate, Never> { get }

    func connect() async
    func disconnect() async
}

// MARK: - Provider Factory

enum ProviderFactory {
    static func createProvider(for config: SourceConfig) -> any ADSBProvider {
        switch config.type {
        case .dump1090:
            return Dump1090Provider(config: config)
        case .beast:
            return BeastProvider(config: config)
        case .sbs:
            return SBSProvider(config: config)
        }
    }
}
