import Foundation
import Combine

class SBSProvider: ADSBProvider, ObservableObject {
    let id: UUID
    let config: SourceConfig

    @Published private(set) var status: ProviderStatus = .disconnected

    var statusPublisher: AnyPublisher<ProviderStatus, Never> {
        $status.eraseToAnyPublisher()
    }

    private let aircraftSubject = PassthroughSubject<AircraftUpdate, Never>()
    var aircraftPublisher: AnyPublisher<AircraftUpdate, Never> {
        aircraftSubject.eraseToAnyPublisher()
    }

    private var tcpConnection: TCPConnection?
    private var buffer = ""
    private var aircraftCache: [String: Aircraft] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(config: SourceConfig) {
        self.id = config.id
        self.config = config
    }

    func connect() async {
        await MainActor.run {
            status = .connecting
        }

        tcpConnection = TCPConnection(host: config.host, port: config.port)

        tcpConnection?.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleConnectionState(state)
            }
            .store(in: &cancellables)

        tcpConnection?.connect { [weak self] data in
            self?.handleData(data)
        }
    }

    func disconnect() async {
        tcpConnection?.disconnect()
        tcpConnection = nil
        cancellables.removeAll()
        buffer = ""

        await MainActor.run {
            status = .disconnected
            aircraftCache.removeAll()
        }
    }

    private func handleConnectionState(_ state: TCPConnection.ConnectionState) {
        switch state {
        case .connected:
            status = .connected(aircraftCount: aircraftCache.count)
        case .connecting:
            status = .connecting
        case .disconnected:
            status = .disconnected
        case .error(let msg):
            status = .error(msg)
        }
    }

    private func handleData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text

        // Process complete lines - split on newline character
        let lines = buffer.components(separatedBy: "\n")
        if lines.count > 1 {
            // Process all complete lines (all but the last one)
            for i in 0..<(lines.count - 1) {
                var line = lines[i]
                // Remove trailing \r if present (CRLF line endings)
                if line.hasSuffix("\r") {
                    line.removeLast()
                }
                if !line.isEmpty {
                    parseSBSMessage(line)
                }
            }
            // Keep the last incomplete line in buffer
            buffer = lines.last ?? ""
        }
    }

    private func parseSBSMessage(_ line: String) {
        let fields = line.components(separatedBy: ",")
        guard fields.count >= 11 else { return }
        guard fields[0] == "MSG" else { return }

        let icaoHex = fields[4].uppercased()
        guard !icaoHex.isEmpty else { return }

        // Get or create aircraft
        var aircraft = aircraftCache[icaoHex] ?? Aircraft(
            icaoHex: icaoHex,
            callsign: nil,
            position: nil,
            altitudeFeet: nil,
            headingDegrees: nil,
            speedKnots: nil,
            verticalRateFpm: nil,
            squawk: nil,
            lastSeen: Date(),
            registration: nil,
            aircraftTypeCode: nil,
            operatorName: nil
        )

        // Update fields based on message type
        // msgType is in fields[1], but we parse all available fields regardless
        // Different message types (1-8) contain different field combinations

        // Callsign (field 10)
        if fields.count > 10 && !fields[10].isEmpty {
            aircraft.callsign = fields[10].trimmingCharacters(in: .whitespaces)
        }

        // Altitude (field 11)
        if fields.count > 11, let alt = Int(fields[11]) {
            aircraft.altitudeFeet = alt
        }

        // Ground speed (field 12)
        if fields.count > 12, let spd = Double(fields[12]) {
            aircraft.speedKnots = spd
        }

        // Track/heading (field 13)
        if fields.count > 13, let hdg = Double(fields[13]) {
            aircraft.headingDegrees = hdg
        }

        // Latitude (field 14)
        if fields.count > 14, let lat = Double(fields[14]) {
            // Longitude (field 15)
            if fields.count > 15, let lon = Double(fields[15]) {
                aircraft.position = Coordinate(latitude: lat, longitude: lon)
            }
        }

        // Vertical rate (field 16)
        if fields.count > 16, let vr = Double(fields[16]) {
            aircraft.verticalRateFpm = vr
        }

        // Squawk (field 17)
        if fields.count > 17 && !fields[17].isEmpty {
            aircraft.squawk = fields[17]
        }

        aircraft.lastSeen = Date()
        aircraftCache[icaoHex] = aircraft

        DispatchQueue.main.async {
            self.status = .connected(aircraftCount: self.aircraftCache.count)
        }

        aircraftSubject.send(.updated(aircraft))
    }
}
