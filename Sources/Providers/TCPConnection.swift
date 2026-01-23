import Foundation
import Network
import Combine

/// Reusable TCP connection wrapper with automatic retry and exponential backoff
class TCPConnection: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int, maxAttempts: Int, nextRetryIn: TimeInterval)
        case error(String)
    }

    struct RetryConfig {
        let maxAttempts: Int
        let baseDelay: TimeInterval
        let maxDelay: TimeInterval
        let jitterFactor: Double

        static let `default` = RetryConfig(
            maxAttempts: 10,
            baseDelay: 1.0,
            maxDelay: 60.0,
            jitterFactor: 0.2
        )

        /// Calculate delay for a given attempt using exponential backoff with jitter
        func delay(forAttempt attempt: Int) -> TimeInterval {
            let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
            let clampedDelay = min(exponentialDelay, maxDelay)
            let jitter = clampedDelay * jitterFactor * Double.random(in: -1...1)
            return max(0.1, clampedDelay + jitter)
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected

    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private var dataHandler: ((Data) -> Void)?
    private let queue = DispatchQueue(label: "TCPConnection")
    private let retryConfig: RetryConfig

    private var retryAttempt = 0
    private var retryTask: Task<Void, Never>?
    private var isIntentionalDisconnect = false

    init(host: String, port: Int, retryConfig: RetryConfig = .default) {
        self.host = host
        self.port = UInt16(port)
        self.retryConfig = retryConfig
    }

    func connect(onData: @escaping (Data) -> Void) {
        self.dataHandler = onData
        self.isIntentionalDisconnect = false
        self.retryAttempt = 0
        attemptConnection()
    }

    func disconnect() {
        isIntentionalDisconnect = true
        retryTask?.cancel()
        retryTask = nil
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async {
            self.state = .disconnected
        }
    }

    private func attemptConnection() {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        // Set connection timeout
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.connectionTimeout = 10
        }

        connection = NWConnection(to: endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleStateUpdate(state)
            }
        }

        DispatchQueue.main.async {
            if self.retryAttempt == 0 {
                self.state = .connecting
            }
        }

        connection?.start(queue: queue)
    }

    private func handleStateUpdate(_ nwState: NWConnection.State) {
        switch nwState {
        case .ready:
            retryAttempt = 0
            state = .connected
            startReceiving()

        case .waiting(let error):
            // Network path not available - schedule retry
            handleConnectionFailure(error: "Network unavailable: \(error.localizedDescription)")

        case .failed(let error):
            handleConnectionFailure(error: error.localizedDescription)

        case .cancelled:
            if !isIntentionalDisconnect {
                handleConnectionFailure(error: "Connection cancelled")
            } else {
                state = .disconnected
            }

        case .preparing:
            if retryAttempt == 0 {
                state = .connecting
            }

        case .setup:
            break

        @unknown default:
            break
        }
    }

    private func handleConnectionFailure(error: String) {
        guard !isIntentionalDisconnect else {
            state = .disconnected
            return
        }

        connection?.cancel()
        connection = nil

        retryAttempt += 1

        if retryAttempt > retryConfig.maxAttempts {
            state = .error("Connection failed after \(retryConfig.maxAttempts) attempts: \(error)")
            return
        }

        let delay = retryConfig.delay(forAttempt: retryAttempt)
        state = .reconnecting(
            attempt: retryAttempt,
            maxAttempts: retryConfig.maxAttempts,
            nextRetryIn: delay
        )

        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard let self = self, !Task.isCancelled, !self.isIntentionalDisconnect else {
                return
            }

            await MainActor.run {
                self.attemptConnection()
            }
        }
    }

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.dataHandler?(data)
            }

            if let error = error {
                DispatchQueue.main.async {
                    self?.handleConnectionFailure(error: error.localizedDescription)
                }
                return
            }

            if isComplete {
                DispatchQueue.main.async {
                    self?.handleConnectionFailure(error: "Connection closed by server")
                }
                return
            }

            // Continue receiving
            self?.startReceiving()
        }
    }
}
