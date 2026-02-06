import Foundation
import Combine

// MARK: - Dump1090 JSON Models

struct Dump1090Response: Codable {
    let now: Double?
    let messages: Int?
    let aircraft: [Dump1090Aircraft]
}

struct Dump1090Aircraft: Codable {
    let hex: String
    let flight: String?
    let lat: Double?
    let lon: Double?
    let altBaro: IntOrString?
    let altGeom: Int?
    let gs: Double?
    let track: Double?
    let baroRate: Int?
    let squawk: String?
    let category: String?
    let seen: Double?
    let rssi: Double?

    enum CodingKeys: String, CodingKey {
        case hex, flight, lat, lon, gs, track, squawk, category, seen, rssi
        case altBaro = "alt_baro"
        case altGeom = "alt_geom"
        case baroRate = "baro_rate"
    }
}

// Handle altitude that can be Int or String ("ground")
enum IntOrString: Codable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(IntOrString.self, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected Int or String"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let val): try container.encode(val)
        case .string(let val): try container.encode(val)
        }
    }

    var intValue: Int? {
        if case .int(let val) = self { return val }
        return nil
    }
}

// MARK: - Dump1090 Provider

class Dump1090Provider: ADSBProvider, ObservableObject {
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

    private var pollingTask: Task<Void, Never>?
    private var isRunning = false

    // Retry configuration
    private let maxRetryAttempts = 10
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 60.0
    private var consecutiveFailures = 0

    /// Message counting for rate calculation
    private var messageCount: Int = 0
    private var rateTimer: Timer?

    init(config: SourceConfig) {
        self.id = config.id
        self.config = config
    }

    private func calculateRetryDelay() -> TimeInterval {
        let exponentialDelay = baseRetryDelay * pow(2.0, Double(consecutiveFailures - 1))
        let clampedDelay = min(exponentialDelay, maxRetryDelay)
        let jitter = clampedDelay * 0.2 * Double.random(in: -1...1)
        return max(0.1, clampedDelay + jitter)
    }

    func connect() async {
        guard !isRunning else { return }
        isRunning = true

        await MainActor.run {
            status = .connecting
        }

        startRateTimer()

        pollingTask = Task { [weak self] in
            guard let self = self else { return }
            await self.pollLoop()
        }
    }

    func disconnect() async {
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil
        stopRateTimer()

        await MainActor.run {
            status = .disconnected
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

    private func pollLoop() async {
        while isRunning && !Task.isCancelled {
            let success = await fetchAircraft()

            let sleepDuration: TimeInterval
            if success {
                consecutiveFailures = 0
                let refreshInterval = await MainActor.run {
                    SettingsManager.shared.refreshInterval
                }
                sleepDuration = refreshInterval
            } else {
                consecutiveFailures += 1

                if consecutiveFailures > maxRetryAttempts {
                    // Stop retrying, show final error
                    await MainActor.run {
                        status = .error("Connection failed after \(maxRetryAttempts) attempts")
                    }
                    return
                }

                sleepDuration = calculateRetryDelay()

                await MainActor.run {
                    status = .reconnecting(attempt: consecutiveFailures, maxAttempts: maxRetryAttempts)
                }
            }

            try? await Task.sleep(nanoseconds: UInt64(sleepDuration * 1_000_000_000))
        }
    }

    @discardableResult
    private func fetchAircraft() async -> Bool {
        let urlString = config.urlString
        guard let url = URL(string: urlString) else {
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            let decoder = JSONDecoder()
            let dump1090Response = try decoder.decode(Dump1090Response.self, from: data)

            let aircraft = dump1090Response.aircraft.compactMap { convertToAircraft($0) }

            // Count each aircraft update as a message
            messageCount += aircraft.count

            await MainActor.run {
                status = .connected(aircraftCount: aircraft.count)
            }

            aircraftSubject.send(.snapshot(aircraft))
            return true

        } catch is CancellationError {
            // Task was cancelled, ignore
            return false
        } catch {
            return false
        }
    }

    private func convertToAircraft(_ d: Dump1090Aircraft) -> Aircraft {
        var position: Coordinate? = nil
        if let lat = d.lat, let lon = d.lon {
            position = Coordinate(latitude: lat, longitude: lon)
        }

        let altitude = d.altBaro?.intValue ?? d.altGeom

        return Aircraft(
            icaoHex: d.hex.uppercased(),
            callsign: d.flight?.trimmingCharacters(in: .whitespaces),
            position: position,
            altitudeFeet: altitude,
            headingDegrees: d.track,
            speedKnots: d.gs,
            verticalRateFpm: d.baroRate.map { Double($0) },
            squawk: d.squawk,
            lastSeen: Date(),
            registration: nil,
            aircraftTypeCode: nil,
            operatorName: nil
        )
    }
}
