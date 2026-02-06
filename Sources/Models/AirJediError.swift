import Foundation

/// Unified error types for AirJedi application
enum AirJediError: LocalizedError {
    // Network errors
    case connectionFailed(host: String, port: Int, underlying: Error?)
    case connectionTimeout(host: String, port: Int)
    case networkUnavailable

    // Parse errors
    case invalidJSON(context: String)
    case invalidMessageFormat(message: String)
    case invalidFrameType(type: UInt8)

    // Configuration errors
    case invalidSourceConfig(reason: String)
    case rulesDecodingFailed(underlying: Error)

    // Location errors
    case locationNotAuthorized
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let host, let port, let error):
            let base = "Failed to connect to \(host):\(port)"
            if let error = error {
                return "\(base): \(error.localizedDescription)"
            }
            return base
        case .connectionTimeout(let host, let port):
            return "Connection to \(host):\(port) timed out"
        case .networkUnavailable:
            return "Network is unavailable"
        case .invalidJSON(let context):
            return "Invalid JSON in \(context)"
        case .invalidMessageFormat(let message):
            return "Invalid message format: \(message)"
        case .invalidFrameType(let type):
            return "Unknown frame type: 0x\(String(format: "%02X", type))"
        case .invalidSourceConfig(let reason):
            return "Invalid source configuration: \(reason)"
        case .rulesDecodingFailed(let error):
            return "Failed to decode alert rules: \(error.localizedDescription)"
        case .locationNotAuthorized:
            return "Location access not authorized"
        case .locationUnavailable:
            return "Unable to determine location"
        }
    }
}
