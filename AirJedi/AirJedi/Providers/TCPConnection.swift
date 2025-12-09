import Foundation
import Network
import Combine

/// Reusable TCP connection wrapper for streaming protocols
class TCPConnection: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    @Published private(set) var state: ConnectionState = .disconnected

    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private var dataHandler: ((Data) -> Void)?
    private let queue = DispatchQueue(label: "TCPConnection")

    init(host: String, port: Int) {
        self.host = host
        self.port = UInt16(port)
    }

    func connect(onData: @escaping (Data) -> Void) {
        self.dataHandler = onData

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        connection = NWConnection(to: endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleStateUpdate(state)
            }
        }

        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async {
            self.state = .disconnected
        }
    }

    private func handleStateUpdate(_ nwState: NWConnection.State) {
        switch nwState {
        case .ready:
            state = .connected
            startReceiving()
        case .waiting(let error):
            state = .error("Waiting: \(error.localizedDescription)")
        case .failed(let error):
            state = .error(error.localizedDescription)
            disconnect()
        case .cancelled:
            state = .disconnected
        case .preparing:
            state = .connecting
        case .setup:
            state = .connecting
        @unknown default:
            break
        }
    }

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.dataHandler?(data)
            }

            if let error = error {
                DispatchQueue.main.async {
                    self?.state = .error(error.localizedDescription)
                }
                return
            }

            if isComplete {
                self?.disconnect()
                return
            }

            // Continue receiving
            self?.startReceiving()
        }
    }
}
