import SwiftUI

struct AircraftListView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            statusHeader

            Divider()

            // Aircraft list
            if appState.aircraft.isEmpty {
                emptyState
            } else {
                aircraftList
            }

            Divider()

            // Footer
            footer

            Divider()

            // Menu items
            menuItems
        }
        .frame(width: 320)
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(appState.connectionStatus.statusText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            if appState.isConnecting {
                ProgressView()
                    .scaleEffect(0.6)
            } else if !appState.connectionStatus.isConnected {
                Button("Connect") {
                    Task {
                        await appState.startProviders()
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch appState.connectionStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            if appState.connectionStatus.isConnected {
                Text("No aircraft detected")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Text("Configure a source in Settings")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Aircraft List

    private var aircraftList: some View {
        ForEach(appState.aircraft) { aircraft in
            AircraftRowView(
                aircraft: aircraft,
                referenceLocation: appState.referenceLocation
            )

            if aircraft.id != appState.aircraft.last?.id {
                Divider()
                    .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(appState.nearbyCount) aircraft")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer()

            if let lastUpdate = appState.aircraftService.lastUpdate {
                Text("Updated \(lastUpdate, style: .relative) ago")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Menu Items

    private var menuItems: some View {
        VStack(spacing: 0) {
            Button("Refresh") {
                Task {
                    await appState.restartProviders()
                }
            }
            .keyboardShortcut("r")
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            SettingsLink {
                Text("Settings...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            Button("Quit AirJedi") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

#Preview {
    AircraftListView(appState: AppState())
}
