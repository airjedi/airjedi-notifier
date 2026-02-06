import Foundation
import Combine

@MainActor
class ProviderManager: ObservableObject {
    @Published private(set) var providers: [any ADSBProvider] = []
    @Published private(set) var combinedStatus: ProviderStatus = .disconnected
    @Published private(set) var totalMessageRate: Double = 0

    private let settings: SettingsManager
    private let aircraftService: AircraftService
    private var cancellables = Set<AnyCancellable>()
    private var statusCancellables = Set<AnyCancellable>()
    private var rateCancellables = Set<AnyCancellable>()

    init(aircraftService: AircraftService, settings: SettingsManager = .shared) {
        self.aircraftService = aircraftService
        self.settings = settings

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

            // Configure Beast providers with reference location for CPR decoding
            if let beastProvider = provider as? BeastProvider {
                beastProvider.configure(referenceLocation: settings.referenceLocation)
            }

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

        // Subscribe to message rate updates
        provider.messageRatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTotalMessageRate()
            }
            .store(in: &rateCancellables)
    }

    private func updateTotalMessageRate() {
        totalMessageRate = providers.reduce(0) { $0 + $1.messageRate }
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
        var hasReconnecting = false
        var maxReconnectAttempt = 0
        var maxReconnectMax = 0

        for provider in providers {
            switch provider.status {
            case .connected(let count):
                hasConnected = true
                totalAircraft += count
            case .connecting:
                hasConnecting = true
            case .reconnecting(let attempt, let max):
                hasReconnecting = true
                if attempt > maxReconnectAttempt {
                    maxReconnectAttempt = attempt
                    maxReconnectMax = max
                }
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
        } else if hasReconnecting {
            combinedStatus = .reconnecting(attempt: maxReconnectAttempt, maxAttempts: maxReconnectMax)
        } else if hasError {
            combinedStatus = .error("Connection failed")
        } else {
            combinedStatus = .disconnected
        }
    }
}
