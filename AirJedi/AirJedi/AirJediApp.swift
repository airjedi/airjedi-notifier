import SwiftUI

@main
struct AirJediApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settings = SettingsManager.shared

    var body: some Scene {
        MenuBarExtra {
            AircraftListView(appState: appState)
        } label: {
            MenuBarIcon(aircraftCount: appState.nearbyCount)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
