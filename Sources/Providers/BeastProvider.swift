import Foundation
import Combine

// MARK: - CPR Data Structures

/// Stores a CPR position message for later decoding
private struct CPRFrame {
    let isOdd: Bool           // F flag: false=even, true=odd
    let latCPR: Int           // 17-bit encoded latitude (0-131071)
    let lonCPR: Int           // 17-bit encoded longitude (0-131071)
    let altitude: Int?        // Altitude from same message
    let timestamp: Date       // When received (for 10-second validity check)
}

/// Per-aircraft CPR state for position decoding
private struct CPRState {
    var evenFrame: CPRFrame?
    var oddFrame: CPRFrame?
    var lastDecodedPosition: Coordinate?
}

// MARK: - Beast Provider

class BeastProvider: ADSBProvider, ObservableObject {
    let id: UUID
    let config: SourceConfig

    @Published private(set) var status: ProviderStatus = .disconnected
    @Published private(set) var messageRate: Double = 0

    var statusPublisher: AnyPublisher<ProviderStatus, Never> {
        $status.eraseToAnyPublisher()
    }

    var messageRatePublisher: AnyPublisher<Double, Never> {
        $messageRate.eraseToAnyPublisher()
    }

    private let aircraftSubject = PassthroughSubject<AircraftUpdate, Never>()
    var aircraftPublisher: AnyPublisher<AircraftUpdate, Never> {
        aircraftSubject.eraseToAnyPublisher()
    }

    private var tcpConnection: TCPConnection?
    private var buffer = Data()
    private var aircraftCache: [String: Aircraft] = [:]
    private var cprStates: [String: CPRState] = [:]  // Per-aircraft CPR tracking
    private var cancellables = Set<AnyCancellable>()

    private let escapeChar: UInt8 = 0x1A

    /// Reference location for local CPR decoding (receiver position)
    private var referenceLocation: Coordinate?

    /// Message counting for rate calculation
    private var messageCount: Int = 0
    private var rateTimer: Timer?

    init(config: SourceConfig) {
        self.id = config.id
        self.config = config
    }

    /// Configure reference location for local CPR decoding
    func configure(referenceLocation: Coordinate) {
        self.referenceLocation = referenceLocation
    }

    func connect() async {
        await MainActor.run {
            status = .connecting
        }

        startRateTimer()

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

    private func startRateTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.rateTimer?.invalidate()
            self.messageCount = 0
            self.messageRate = 0

            self.rateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.messageRate = Double(self.messageCount)
                self.messageCount = 0
            }
        }
    }

    private func stopRateTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.rateTimer?.invalidate()
            self.rateTimer = nil
            self.messageRate = 0
            self.messageCount = 0
        }
    }

    func disconnect() async {
        stopRateTimer()
        tcpConnection?.disconnect()
        tcpConnection = nil
        cancellables.removeAll()
        buffer = Data()

        await MainActor.run {
            status = .disconnected
            aircraftCache.removeAll()
            cprStates.removeAll()
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
        case .reconnecting(let attempt, let maxAttempts, _):
            status = .reconnecting(attempt: attempt, maxAttempts: maxAttempts)
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
                messageCount += 1
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
            if let (alt, position) = parseAirbornePosition(data, icaoHex: icaoHex) {
                aircraft.altitudeFeet = alt
                if let position = position {
                    aircraft.position = position
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

        // Clean up stale CPR states periodically
        cleanupStaleCPRStates()

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

    // MARK: - CPR Position Decoding

    private func parseAirbornePosition(_ data: Data, icaoHex: String) -> (Int?, Coordinate?)? {
        guard data.count >= 11 else { return nil }

        // Altitude (12 bits): ME bits 9-20
        // data[5] = altitude bits 1-8 (MSB), data[6] bits 7-4 = altitude bits 9-12 (LSB)
        let altBits = (Int(data[5]) << 4) | ((Int(data[6]) >> 4) & 0x0F)

        // Q-bit is bit 5 of the 12-bit altitude field (determines encoding)
        let qBit = (altBits >> 4) & 1
        var altitude: Int?

        if qBit == 1 {
            // 25ft resolution: remove Q-bit and compute
            // Altitude bits: 11 10 9 8 7 6 [Q] 4 3 2 1 0
            let n = ((altBits >> 5) << 4) | (altBits & 0x0F)
            altitude = n * 25 - 1000
        } else {
            // Gillham (100ft) encoding - more complex, decode if needed
            // For now, attempt simple decode (works for most altitudes)
            let n = ((altBits >> 5) << 4) | (altBits & 0x0F)
            if n > 0 {
                altitude = n * 100 - 1000
            }
        }

        // Extract CPR fields
        // F flag (odd/even) is bit 22 of the message (bit 2 of byte 6, after TC and altitude)
        let isOdd = (data[6] & 0x04) != 0

        // Latitude CPR: 17 bits starting at bit 23 (bits 1-0 of byte 6, all of byte 7, bits 7-1 of byte 8)
        let latCPR = (Int(data[6] & 0x03) << 15) | (Int(data[7]) << 7) | (Int(data[8]) >> 1)

        // Longitude CPR: 17 bits starting at bit 40 (bit 0 of byte 8, all of bytes 9-10)
        let lonCPR = (Int(data[8] & 0x01) << 16) | (Int(data[9]) << 8) | Int(data[10])

        let frame = CPRFrame(isOdd: isOdd, latCPR: latCPR, lonCPR: lonCPR,
                             altitude: altitude, timestamp: Date())

        // Store frame in CPR state
        var state = cprStates[icaoHex] ?? CPRState()
        if isOdd {
            state.oddFrame = frame
        } else {
            state.evenFrame = frame
        }

        // Attempt position decoding
        var position: Coordinate?

        // Try global decode first (both frames within 10 seconds)
        if let even = state.evenFrame, let odd = state.oddFrame,
           abs(even.timestamp.timeIntervalSince(odd.timestamp)) < 10 {
            position = decodeGlobalPosition(even: even, odd: odd)
        }

        // Fallback to local decode
        if position == nil {
            let ref = state.lastDecodedPosition ?? referenceLocation
            if let ref = ref {
                position = decodeLocalPosition(frame: frame, reference: ref)
            }
        }

        // Update state
        if let pos = position {
            state.lastDecodedPosition = pos
        }
        cprStates[icaoHex] = state

        return (altitude, position)
    }

    /// Global CPR decoding using both even and odd frames
    private func decodeGlobalPosition(even: CPRFrame, odd: CPRFrame) -> Coordinate? {
        let cprMax = 131072.0  // 2^17

        let latCPR0 = Double(even.latCPR) / cprMax
        let latCPR1 = Double(odd.latCPR) / cprMax
        let lonCPR0 = Double(even.lonCPR) / cprMax
        let lonCPR1 = Double(odd.lonCPR) / cprMax

        // Latitude zone sizes
        let dLat0 = 360.0 / 60.0  // 6° for even
        let dLat1 = 360.0 / 59.0  // ~6.1° for odd

        // Compute latitude index j
        let j = floor(59.0 * latCPR0 - 60.0 * latCPR1 + 0.5)

        // Compute latitudes
        var latEven = dLat0 * (cprMod(j, 60) + latCPR0)
        var latOdd = dLat1 * (cprMod(j, 59) + latCPR1)

        // Adjust for southern hemisphere
        if latEven >= 270 { latEven -= 360 }
        if latOdd >= 270 { latOdd -= 360 }

        // Check zone consistency
        let nlEven = cprNL(latEven)
        let nlOdd = cprNL(latOdd)
        guard nlEven == nlOdd else { return nil }

        // Use most recent frame
        let useOdd = odd.timestamp > even.timestamp
        let lat = useOdd ? latOdd : latEven
        let lonCPR = useOdd ? lonCPR1 : lonCPR0
        let nl = useOdd ? nlOdd : nlEven
        let ni = useOdd ? max(1, nl - 1) : max(1, nl)

        // Compute longitude
        let dLon = 360.0 / Double(ni)
        let m = floor(Double(even.lonCPR) * Double(nl - 1) / cprMax -
                      Double(odd.lonCPR) * Double(nl) / cprMax + 0.5)
        var lon = dLon * (cprMod(m, Double(ni)) + lonCPR)

        if lon > 180 { lon -= 360 }

        // Validate position
        guard lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 else {
            return nil
        }

        return Coordinate(latitude: lat, longitude: lon)
    }

    /// Local CPR decoding using a reference position
    private func decodeLocalPosition(frame: CPRFrame, reference: Coordinate) -> Coordinate? {
        let cprMax = 131072.0  // 2^17

        let latCPR = Double(frame.latCPR) / cprMax
        let lonCPR = Double(frame.lonCPR) / cprMax

        // Latitude zone size
        let dLat = frame.isOdd ? 360.0 / 59.0 : 360.0 / 60.0

        // Find latitude zone index
        let j = floor(reference.latitude / dLat) +
                floor(0.5 + cprMod(reference.latitude, dLat) / dLat - latCPR)

        // Compute latitude
        let lat = dLat * (j + latCPR)

        // Validate latitude
        guard lat >= -90 && lat <= 90 else { return nil }

        // Longitude zone size depends on latitude
        let nl = cprNL(lat)
        let ni = frame.isOdd ? max(1, nl - 1) : max(1, nl)
        let dLon = 360.0 / Double(ni)

        // Find longitude zone index
        let m = floor(reference.longitude / dLon) +
                floor(0.5 + cprMod(reference.longitude, dLon) / dLon - lonCPR)

        // Compute longitude
        var lon = dLon * (m + lonCPR)

        // Normalize longitude to -180...180
        if lon > 180 { lon -= 360 }
        if lon < -180 { lon += 360 }

        // Validate position
        guard lon >= -180 && lon <= 180 else { return nil }

        // Sanity check: decoded position shouldn't be too far from reference
        // (local decoding fails beyond ~250nm)
        let distance = approximateDistance(from: reference, to: Coordinate(latitude: lat, longitude: lon))
        guard distance < 500 else { return nil }  // 500nm sanity limit

        return Coordinate(latitude: lat, longitude: lon)
    }

    /// Approximate distance in nautical miles (simple spherical)
    private func approximateDistance(from: Coordinate, to: Coordinate) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))

        return 3440.065 * c  // Earth radius in nm
    }

    /// CPR modulo operation (always positive result)
    private func cprMod(_ a: Double, _ b: Double) -> Double {
        let result = a.truncatingRemainder(dividingBy: b)
        return result >= 0 ? result : result + b
    }

    /// Number of Longitude zones (NL) for a given latitude
    /// Based on precomputed latitude thresholds
    private func cprNL(_ lat: Double) -> Int {
        let absLat = abs(lat)

        // NL lookup table - latitude thresholds for each NL value
        // NL decreases as latitude increases (fewer zones near poles)
        if absLat < 10.47047130 { return 59 }
        if absLat < 14.82817437 { return 58 }
        if absLat < 18.18626357 { return 57 }
        if absLat < 21.02939493 { return 56 }
        if absLat < 23.54504487 { return 55 }
        if absLat < 25.82924707 { return 54 }
        if absLat < 27.93898710 { return 53 }
        if absLat < 29.91135686 { return 52 }
        if absLat < 31.77209708 { return 51 }
        if absLat < 33.53993436 { return 50 }
        if absLat < 35.22899598 { return 49 }
        if absLat < 36.85025108 { return 48 }
        if absLat < 38.41241892 { return 47 }
        if absLat < 39.92256684 { return 46 }
        if absLat < 41.38651832 { return 45 }
        if absLat < 42.80914012 { return 44 }
        if absLat < 44.19454951 { return 43 }
        if absLat < 45.54626723 { return 42 }
        if absLat < 46.86733252 { return 41 }
        if absLat < 48.16039128 { return 40 }
        if absLat < 49.42776439 { return 39 }
        if absLat < 50.67150166 { return 38 }
        if absLat < 51.89342469 { return 37 }
        if absLat < 53.09516153 { return 36 }
        if absLat < 54.27817472 { return 35 }
        if absLat < 55.44378444 { return 34 }
        if absLat < 56.59318756 { return 33 }
        if absLat < 57.72747354 { return 32 }
        if absLat < 58.84763776 { return 31 }
        if absLat < 59.95459277 { return 30 }
        if absLat < 61.04917774 { return 29 }
        if absLat < 62.13216659 { return 28 }
        if absLat < 63.20427479 { return 27 }
        if absLat < 64.26616523 { return 26 }
        if absLat < 65.31845310 { return 25 }
        if absLat < 66.36171008 { return 24 }
        if absLat < 67.39646774 { return 23 }
        if absLat < 68.42322022 { return 22 }
        if absLat < 69.44242631 { return 21 }
        if absLat < 70.45451075 { return 20 }
        if absLat < 71.45986473 { return 19 }
        if absLat < 72.45884545 { return 18 }
        if absLat < 73.45177442 { return 17 }
        if absLat < 74.43893416 { return 16 }
        if absLat < 75.42056257 { return 15 }
        if absLat < 76.39684391 { return 14 }
        if absLat < 77.36789461 { return 13 }
        if absLat < 78.33374083 { return 12 }
        if absLat < 79.29428225 { return 11 }
        if absLat < 80.24923213 { return 10 }
        if absLat < 81.19801349 { return 9 }
        if absLat < 82.13956981 { return 8 }
        if absLat < 83.07199445 { return 7 }
        if absLat < 83.99173563 { return 6 }
        if absLat < 84.89166191 { return 5 }
        if absLat < 85.75541621 { return 4 }
        if absLat < 86.53536998 { return 3 }
        if absLat < 87.00000000 { return 2 }
        return 1
    }

    private func cleanupStaleCPRStates() {
        let now = Date()
        let maxAge: TimeInterval = 60  // Match aircraft stale threshold

        cprStates = cprStates.filter { (icaoHex, state) in
            // Keep if aircraft still in cache
            guard aircraftCache[icaoHex] != nil else { return false }

            // Keep if any frame is recent
            let evenAge = state.evenFrame.map { now.timeIntervalSince($0.timestamp) } ?? .infinity
            let oddAge = state.oddFrame.map { now.timeIntervalSince($0.timestamp) } ?? .infinity
            return min(evenAge, oddAge) < maxAge
        }
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
