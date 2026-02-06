import Foundation
import Combine

@MainActor
class AircraftService: ObservableObject {
    @Published private(set) var aircraft: [Aircraft] = []
    @Published private(set) var lastUpdate: Date?

    private var aircraftCache: [String: Aircraft] = [:]  // icaoHex -> Aircraft
    private var cancellables = Set<AnyCancellable>()
    private var staleTimer: Timer?

    private let settings: SettingsManager

    init(settings: SettingsManager = .shared) {
        self.settings = settings
        startStaleTimer()
    }

    deinit {
        staleTimer?.invalidate()
    }

    // MARK: - Provider Subscription

    func subscribe(to provider: any ADSBProvider) {
        provider.aircraftPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.processUpdate(update)
            }
            .store(in: &cancellables)
    }

    func unsubscribeAll() {
        cancellables.removeAll()
    }

    // MARK: - Update Processing

    private func processUpdate(_ update: AircraftUpdate) {
        switch update {
        case .updated(let aircraft):
            aircraftCache[aircraft.icaoHex] = aircraft

        case .removed(let icaoHex):
            aircraftCache.removeValue(forKey: icaoHex)

        case .snapshot(let aircraftList):
            // Replace cache with snapshot
            var newCache: [String: Aircraft] = [:]
            for ac in aircraftList {
                newCache[ac.icaoHex] = ac
            }
            aircraftCache = newCache
        }

        updatePublishedAircraft()
    }

    private func updatePublishedAircraft() {
        let showWithoutPosition = settings.showAircraftWithoutPosition
        let maxDisplay = settings.maxAircraftDisplay
        let referenceLocation = settings.referenceLocation

        var filtered = Array(aircraftCache.values)

        // Filter out aircraft without position if setting is off
        if !showWithoutPosition {
            filtered = filtered.filter { $0.position != nil }
        }

        // Sort by distance
        filtered.sort { a, b in
            let distA = a.distance(from: referenceLocation) ?? .infinity
            let distB = b.distance(from: referenceLocation) ?? .infinity
            return distA < distB
        }

        // Limit to max display
        if filtered.count > maxDisplay && maxDisplay < 999 {
            filtered = Array(filtered.prefix(maxDisplay))
        }

        aircraft = filtered
        lastUpdate = Date()
    }

    // MARK: - Stale Aircraft Removal

    private func startStaleTimer() {
        staleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.removeStaleAircraft()
            }
        }
    }

    private func removeStaleAircraft() {
        let threshold = TimeInterval(settings.staleThresholdSeconds)
        let now = Date()

        var removedAny = false
        for (icaoHex, aircraft) in aircraftCache {
            if now.timeIntervalSince(aircraft.lastSeen) > threshold {
                aircraftCache.removeValue(forKey: icaoHex)
                removedAny = true
            }
        }

        if removedAny {
            updatePublishedAircraft()
        }
    }

    // MARK: - Manual Refresh

    func clearAll() {
        aircraftCache.removeAll()
        aircraft = []
    }
}
