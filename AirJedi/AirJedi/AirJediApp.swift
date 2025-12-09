import SwiftUI

@main
struct AirJediApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            AircraftListView(appState: appState)
        } label: {
            MenuBarIcon(
                aircraftCount: appState.nearbyCount,
                status: appState.connectionStatus,
                hasAlert: appState.hasRecentAlert
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
