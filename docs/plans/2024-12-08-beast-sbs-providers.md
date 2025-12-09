# Beast & SBS Providers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement BeastProvider and SBSProvider for real-time TCP streaming from ADS-B receivers, complementing the existing Dump1090Provider.

**Architecture:** Both providers use TCP sockets with NWConnection. Beast parses binary AVR frames, SBS parses CSV-like text lines. Both emit incremental `.updated` events instead of `.snapshot`.

**Tech Stack:** Swift 5.9+, Network.framework (NWConnection), async/await

---

## Task 1: Create TCP Connection Helper

**Files:**
- Create: `AirJedi/AirJedi/Providers/TCPConnection.swift`

**Step 1: Create reusable TCP connection wrapper**

Create file `AirJedi/AirJedi/Providers/TCPConnection.swift`:

```swift
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
```

**Step 2: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Providers/TCPConnection.swift
git commit -m "Add TCPConnection helper for streaming protocols"
```

---

## Task 2: Create SBSProvider

**Files:**
- Create: `AirJedi/AirJedi/Providers/SBSProvider.swift`

**Step 1: Create the SBS BaseStation provider**

SBS format is CSV-like text, one message per line. Format:
`MSG,3,1,1,ICAO,1,2024/01/01,12:00:00.000,2024/01/01,12:00:00.000,CALLSIGN,ALT,SPD,HDG,LAT,LON,VERTRATE,...`

Create file `AirJedi/AirJedi/Providers/SBSProvider.swift`:

```swift
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

        // Process complete lines
        while let lineEnd = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<lineEnd])
            buffer = String(buffer[buffer.index(after: lineEnd)...])

            if !line.isEmpty {
                parseSBSMessage(line)
            }
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
        let msgType = Int(fields[1]) ?? 0

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
```

**Step 2: Update ProviderFactory to support SBS**

Edit `AirJedi/AirJedi/Providers/ADSBProvider.swift`, update the factory:

```swift
enum ProviderFactory {
    static func createProvider(for config: SourceConfig) -> any ADSBProvider {
        switch config.type {
        case .dump1090:
            return Dump1090Provider(config: config)
        case .beast:
            // TODO: Implement BeastProvider
            fatalError("Beast provider not yet implemented")
        case .sbs:
            return SBSProvider(config: config)
        }
    }
}
```

**Step 3: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 4: Commit**

```bash
git add AirJedi/AirJedi/Providers/SBSProvider.swift
git add AirJedi/AirJedi/Providers/ADSBProvider.swift
git commit -m "Add SBSProvider for BaseStation TCP protocol"
```

---

## Task 3: Create BeastProvider

**Files:**
- Create: `AirJedi/AirJedi/Providers/BeastProvider.swift`

**Step 1: Create the Beast binary protocol provider**

Beast format is binary with escape sequences. Each frame starts with 0x1A followed by type byte:
- 0x31: Mode-AC (2 bytes)
- 0x32: Mode-S short (7 bytes)
- 0x33: Mode-S long (14 bytes)

The 14-byte extended squitter contains the ADS-B message.

Create file `AirJedi/AirJedi/Providers/BeastProvider.swift`:

```swift
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

        DispatchQueue.main.async {
            self.status = .connected(aircraftCount: self.aircraftCache.count)
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
```

**Step 2: Update ProviderFactory to support Beast**

Edit `AirJedi/AirJedi/Providers/ADSBProvider.swift`:

```swift
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
```

**Step 3: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 4: Commit**

```bash
git add AirJedi/AirJedi/Providers/BeastProvider.swift
git add AirJedi/AirJedi/Providers/ADSBProvider.swift
git commit -m "Add BeastProvider for binary AVR protocol"
```

---

## Summary

After completing all tasks, you will have:
- TCPConnection helper for reusable TCP socket management
- SBSProvider parsing BaseStation CSV format on port 30003
- BeastProvider parsing binary AVR frames on port 30005
- All three provider types (dump1090, Beast, SBS) fully functional

Users can now configure any of the three source types in Settings and receive live aircraft data.
