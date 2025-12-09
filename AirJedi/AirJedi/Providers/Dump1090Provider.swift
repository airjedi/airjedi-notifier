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

    var statusPublisher: AnyPublisher<ProviderStatus, Never> {
        $status.eraseToAnyPublisher()
    }

    private let aircraftSubject = PassthroughSubject<AircraftUpdate, Never>()
    var aircraftPublisher: AnyPublisher<AircraftUpdate, Never> {
        aircraftSubject.eraseToAnyPublisher()
    }

    private var pollingTask: Task<Void, Never>?
    private var isRunning = false

    init(config: SourceConfig) {
        self.id = config.id
        self.config = config
    }

    func connect() async {
        guard !isRunning else { return }
        isRunning = true

        await MainActor.run {
            status = .connecting
        }

        pollingTask = Task { [weak self] in
            guard let self = self else { return }
            await self.pollLoop()
        }
    }

    func disconnect() async {
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil

        await MainActor.run {
            status = .disconnected
        }
    }

    private func pollLoop() async {
        while isRunning && !Task.isCancelled {
            await fetchAircraft()

            let refreshInterval = await MainActor.run {
                SettingsManager.shared.refreshInterval
            }
            try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
        }
    }

    private func fetchAircraft() async {
        let urlString = config.urlString
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                status = .error("Invalid URL: \(urlString)")
            }
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    status = .error("Invalid response")
                }
                return
            }

            guard httpResponse.statusCode == 200 else {
                await MainActor.run {
                    status = .error("HTTP \(httpResponse.statusCode)")
                }
                return
            }

            let decoder = JSONDecoder()
            let dump1090Response = try decoder.decode(Dump1090Response.self, from: data)

            let aircraft = dump1090Response.aircraft.compactMap { convertToAircraft($0) }

            await MainActor.run {
                status = .connected(aircraftCount: aircraft.count)
            }

            aircraftSubject.send(.snapshot(aircraft))

        } catch is CancellationError {
            // Task was cancelled, ignore
        } catch {
            await MainActor.run {
                status = .error(error.localizedDescription)
            }
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
