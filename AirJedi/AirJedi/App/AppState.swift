import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isConnecting = false

    let aircraftService: AircraftService
    let providerManager: ProviderManager

    private let settings = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    var aircraft: [Aircraft] {
        aircraftService.aircraft
    }

    var nearbyCount: Int {
        aircraftService.aircraft.count
    }

    var referenceLocation: Coordinate {
        settings.referenceLocation
    }

    var connectionStatus: ProviderStatus {
        providerManager.combinedStatus
    }

    init() {
        self.aircraftService = AircraftService()
        self.providerManager = ProviderManager(aircraftService: aircraftService)

        // Forward changes from services to trigger view updates
        aircraftService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        providerManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Auto-start providers if sources are configured
        Task {
            await startProviders()
        }
    }

    func startProviders() async {
        isConnecting = true
        await providerManager.startAll()
        isConnecting = false
    }

    func stopProviders() async {
        await providerManager.stopAll()
    }

    func restartProviders() async {
        isConnecting = true
        await providerManager.restart()
        isConnecting = false
    }
}
