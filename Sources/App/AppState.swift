import SwiftUI
import Combine
import Observation

@Observable
@MainActor
class AppState {
    // Stored properties for menu bar label (tracked by @Observable)
    var isConnecting = false
    var nearbyCount: Int = 0
    var connectionStatus: ProviderStatus = .disconnected
    var hasRecentAlert: Bool = false

    let aircraftService: AircraftService
    let providerManager: ProviderManager
    let alertEngine: AlertEngine
    let notificationManager: NotificationManager

    private let settings = SettingsManager.shared
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    var aircraft: [Aircraft] {
        aircraftService.aircraft
    }

    var referenceLocation: Coordinate {
        settings.referenceLocation
    }

    var recentAlerts: [Alert] {
        alertEngine.recentAlerts
    }

    init() {
        self.aircraftService = AircraftService()
        self.providerManager = ProviderManager(aircraftService: aircraftService)
        self.alertEngine = AlertEngine()
        self.notificationManager = NotificationManager.shared

        // Sync stored properties from services for menu bar updates
        aircraftService.$aircraft
            .receive(on: RunLoop.main)
            .sink { [weak self] aircraft in
                self?.nearbyCount = aircraft.count
                self?.evaluateAlerts()
            }
            .store(in: &cancellables)

        providerManager.$combinedStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.connectionStatus = status
            }
            .store(in: &cancellables)

        alertEngine.$recentAlerts
            .receive(on: RunLoop.main)
            .sink { [weak self] alerts in
                if let mostRecent = alerts.first {
                    self?.hasRecentAlert = Date().timeIntervalSince(mostRecent.timestamp) < 30
                } else {
                    self?.hasRecentAlert = false
                }
            }
            .store(in: &cancellables)

        // Re-evaluate alert colors when rules change
        alertEngine.$alertRules
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAlertColors()
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

    private func refreshAlertColors() {
        alertEngine.updateActiveAlerts(aircraft: aircraftService.aircraft)
    }

    private func evaluateAlerts() {
        let currentAircraft = aircraftService.aircraft

        // Update highlight colors for matching alerts
        alertEngine.updateActiveAlerts(aircraft: currentAircraft)

        // Evaluate for notifications
        let newAlerts = alertEngine.evaluate(aircraft: currentAircraft)
        if !newAlerts.isEmpty {
            Task {
                await notificationManager.deliverMultiple(newAlerts)
            }
        }
    }
}
