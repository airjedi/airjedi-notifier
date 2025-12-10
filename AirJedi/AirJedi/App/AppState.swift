import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isConnecting = false
    @Published private(set) var nearbyCount: Int = 0

    let aircraftService: AircraftService
    let providerManager: ProviderManager
    let alertEngine: AlertEngine
    let notificationManager: NotificationManager

    private let settings = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    var aircraft: [Aircraft] {
        aircraftService.aircraft
    }


    var referenceLocation: Coordinate {
        settings.referenceLocation
    }

    var connectionStatus: ProviderStatus {
        providerManager.combinedStatus
    }

    var recentAlerts: [Alert] {
        alertEngine.recentAlerts
    }

    var hasRecentAlert: Bool {
        if let mostRecent = alertEngine.recentAlerts.first {
            return Date().timeIntervalSince(mostRecent.timestamp) < 30
        }
        return false
    }

    init() {
        self.aircraftService = AircraftService()
        self.providerManager = ProviderManager(aircraftService: aircraftService)
        self.alertEngine = AlertEngine()
        self.notificationManager = NotificationManager.shared

        // Forward changes from services to trigger view updates
        aircraftService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.evaluateAlerts()
            }
            .store(in: &cancellables)

        // Subscribe to aircraft changes to update count (uses $aircraft for post-change value)
        aircraftService.$aircraft
            .map { $0.count }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.nearbyCount = count
            }
            .store(in: &cancellables)

        providerManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        alertEngine.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Request notification permission
        Task {
            await notificationManager.requestPermission()
        }

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

    private func evaluateAlerts() {
        let newAlerts = alertEngine.evaluate(aircraft: aircraftService.aircraft)
        if !newAlerts.isEmpty {
            Task {
                await notificationManager.deliverMultiple(newAlerts)
            }
        }
    }
}
