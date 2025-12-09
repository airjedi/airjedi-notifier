import Foundation
import Combine

class BeastProvider: ADSBProvider, ObservableObject {
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
    private var buffer = Data()
    private var aircraftCache: [String: Aircraft] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let escapeChar: UInt8 = 0x1A

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
        buffer = Data()

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
        buffer.append(data)
        processBuffer()
    }

    private func processBuffer() {
        while !buffer.isEmpty {
            // Find escape character
            guard let escapeIndex = buffer.firstIndex(of: escapeChar) else {
                buffer.removeAll()
                return
            }

            // Remove data before escape
            if escapeIndex > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<escapeIndex)
            }

            // Need at least 2 bytes (escape + type)
            guard buffer.count >= 2 else { return }

            let frameType = buffer[buffer.index(after: buffer.startIndex)]
            let payloadLength: Int

            switch frameType {
            case 0x31: payloadLength = 2   // Mode-AC
            case 0x32: payloadLength = 7   // Mode-S short
            case 0x33: payloadLength = 14  // Mode-S extended squitter
            default:
                // Unknown frame type, skip escape byte
                buffer.removeFirst()
                continue
            }

            // Need: escape(1) + type(1) + timestamp(6) + signal(1) + payload
            let frameLength = 1 + 1 + 6 + 1 + payloadLength
            guard buffer.count >= frameLength else { return }

            // Extract frame (skip escape and type)
            let timestampStart = buffer.index(buffer.startIndex, offsetBy: 2)
            let signalStart = buffer.index(timestampStart, offsetBy: 6)
            let payloadStart = buffer.index(signalStart, offsetBy: 1)
            let payloadEnd = buffer.index(payloadStart, offsetBy: payloadLength)

            let payload = Data(buffer[payloadStart..<payloadEnd])

            // Remove processed frame
            buffer.removeSubrange(buffer.startIndex..<payloadEnd)

            // Only process extended squitter (14 bytes)
            if frameType == 0x33 && payload.count == 14 {
                parseExtendedSquitter(payload)
            }
        }
    }

    private func parseExtendedSquitter(_ data: Data) {
        guard data.count >= 14 else { return }

        // First 4 bytes: DF (5 bits) + CA (3 bits) + ICAO (24 bits)
        let df = (data[0] >> 3) & 0x1F
        guard df == 17 || df == 18 else { return }  // ADS-B messages

        let icaoHex = String(format: "%02X%02X%02X", data[1], data[2], data[3])

        // Type code is in first 5 bits of byte 4
        let typeCode = (data[4] >> 3) & 0x1F

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

        // Parse based on type code
        switch typeCode {
        case 1...4:  // Aircraft identification
            aircraft.callsign = parseCallsign(data)
        case 9...18:  // Airborne position (barometric altitude)
            if let (alt, lat, lon) = parseAirbornePosition(data) {
                aircraft.altitudeFeet = alt
                if let lat = lat, let lon = lon {
                    aircraft.position = Coordinate(latitude: lat, longitude: lon)
                }
            }
        case 19:  // Airborne velocity
            if let (speed, heading, vr) = parseVelocity(data) {
                aircraft.speedKnots = speed
                aircraft.headingDegrees = heading
                aircraft.verticalRateFpm = vr
            }
        default:
            break
        }

        aircraft.lastSeen = Date()
        aircraftCache[icaoHex] = aircraft

        let count = aircraftCache.count
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.status = .connected(aircraftCount: count)
        }

        aircraftSubject.send(.updated(aircraft))
    }

    private func parseCallsign(_ data: Data) -> String? {
        guard data.count >= 11 else { return nil }

        let charset = "?ABCDEFGHIJKLMNOPQRSTUVWXYZ????? ???????????????0123456789??????"
        var callsign = ""

        // 8 characters packed in 48 bits (6 bits each)
        let bytes = Array(data[5...10])
        let bits = bytes.reduce(0 as UInt64) { ($0 << 8) | UInt64($1) }

        for i in 0..<8 {
            let shift = (7 - i) * 6
            let idx = Int((bits >> shift) & 0x3F)
            let charIndex = charset.index(charset.startIndex, offsetBy: idx)
            callsign.append(charset[charIndex])
        }

        let trimmed = callsign.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseAirbornePosition(_ data: Data) -> (Int?, Double?, Double?)? {
        guard data.count >= 11 else { return nil }

        // Altitude (12 bits in bytes 5-6)
        let altBits = (Int(data[5] & 0x07) << 9) | (Int(data[6]) << 1) | (Int(data[7] >> 7))

        // Q bit determines encoding
        let qBit = (altBits >> 4) & 1
        var altitude: Int?

        if qBit == 1 {
            // 25ft resolution
            let n = ((altBits >> 5) << 4) | (altBits & 0x0F)
            altitude = n * 25 - 1000
        }

        // CPR latitude and longitude (simplified - would need even/odd frame handling for accuracy)
        // For now, we rely on position being filled in by dump1090/SBS if available
        return (altitude, nil, nil)
    }

    private func parseVelocity(_ data: Data) -> (Double?, Double?, Double?)? {
        guard data.count >= 11 else { return nil }

        let subtype = data[4] & 0x07

        if subtype == 1 || subtype == 2 {
            // Ground speed
            let ewSign = (data[5] >> 2) & 1
            let ewVel = (Int(data[5] & 0x03) << 8) | Int(data[6])
            let nsSign = (data[7] >> 7) & 1
            let nsVel = (Int(data[7] & 0x7F) << 3) | Int(data[8] >> 5)

            let ew = Double(ewVel - 1) * (ewSign == 1 ? -1 : 1)
            let ns = Double(nsVel - 1) * (nsSign == 1 ? -1 : 1)

            let speed = sqrt(ew * ew + ns * ns)
            var heading = atan2(ew, ns) * 180 / .pi
            if heading < 0 { heading += 360 }

            // Vertical rate
            let vrSign = (data[8] >> 3) & 1
            let vrBits = (Int(data[8] & 0x07) << 6) | Int(data[9] >> 2)
            let vr = Double(vrBits - 1) * 64 * (vrSign == 1 ? -1 : 1)

            return (speed, heading, vr)
        }

        return nil
    }
}
