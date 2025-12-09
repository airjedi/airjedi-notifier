import Foundation
import Combine

@MainActor
class ProviderManager: ObservableObject {
    @Published private(set) var providers: [any ADSBProvider] = []
    @Published private(set) var combinedStatus: ProviderStatus = .disconnected

    private let settings = SettingsManager.shared
    private let aircraftService: AircraftService
    private var cancellables = Set<AnyCancellable>()
    private var statusCancellables = Set<AnyCancellable>()

    init(aircraftService: AircraftService) {
        self.aircraftService = aircraftService

        // Observe settings changes
        settings.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.syncProviders()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Provider Lifecycle

    func startAll() async {
        await syncProviders()

        for provider in providers {
            await provider.connect()
        }

        updateCombinedStatus()
    }

    func stopAll() async {
        for provider in providers {
            await provider.disconnect()
        }

        aircraftService.clearAll()
        updateCombinedStatus()
    }

    func restart() async {
        await stopAll()
        await startAll()
    }

    // MARK: - Provider Sync

    private func syncProviders() async {
        let enabledConfigs = settings.sources.filter { $0.isEnabled }
        let existingIds = Set(providers.map { $0.id })
        let configIds = Set(enabledConfigs.map { $0.id })

        // Remove providers that are no longer in config
        for provider in providers where !configIds.contains(provider.id) {
            await provider.disconnect()
        }
        providers.removeAll { !configIds.contains($0.id) }

        // Add new providers
        for config in enabledConfigs where !existingIds.contains(config.id) {
            let provider = ProviderFactory.createProvider(for: config)
            providers.append(provider)
            subscribeToProvider(provider)
        }

        updateCombinedStatus()
    }

    private func subscribeToProvider(_ provider: any ADSBProvider) {
        // Subscribe AircraftService to updates
        aircraftService.subscribe(to: provider)

        // Subscribe to status updates
        provider.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCombinedStatus()
            }
            .store(in: &statusCancellables)
    }

    // MARK: - Combined Status

    private func updateCombinedStatus() {
        if providers.isEmpty {
            combinedStatus = .disconnected
            return
        }

        var totalAircraft = 0
        var hasError = false
        var hasConnecting = false
        var hasConnected = false

        for provider in providers {
            switch provider.status {
            case .connected(let count):
                hasConnected = true
                totalAircraft += count
            case .connecting:
                hasConnecting = true
            case .error:
                hasError = true
            case .disconnected:
                break
            }
        }

        if hasConnected {
            combinedStatus = .connected(aircraftCount: totalAircraft)
        } else if hasConnecting {
            combinedStatus = .connecting
        } else if hasError {
            combinedStatus = .error("Connection failed")
        } else {
            combinedStatus = .disconnected
        }
    }
}
