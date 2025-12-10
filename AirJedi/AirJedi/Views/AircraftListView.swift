import SwiftUI

struct AircraftListView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.openSettings) private var openSettings

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

            Button {
                settings.soundsMuted.toggle()
            } label: {
                Image(systemName: settings.soundsMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(settings.soundsMuted ? .orange : .secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("m")
            .help(settings.soundsMuted ? "Unmute Sounds" : "Mute Sounds")

            Button {
                openSettings()
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    if let settingsWindow = NSApp.windows.first(where: { $0.title.contains("Settings") || $0.identifier?.rawValue.contains("settings") == true }) {
                        settingsWindow.makeKeyAndOrderFront(nil)
                    } else {
                        NSApp.windows.last?.makeKeyAndOrderFront(nil)
                    }
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings")

            Button {
                Task {
                    await appState.restartProviders()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r")
            .help("Refresh")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
            .help("Quit AirJedi")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch appState.connectionStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .reconnecting: return .orange
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

    /// Maximum height for the aircraft list scroll area (approximately 15 rows)
    private let maxListHeight: CGFloat = 600

    private var aircraftList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
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
        }
        .frame(maxHeight: maxListHeight)
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

}

#Preview {
    AircraftListView(appState: AppState())
}
