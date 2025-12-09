import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case sources = "Sources"
    case location = "Location"
    case display = "Display"
    case alerts = "Alerts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sources: return "antenna.radiowaves.left.and.right"
        case .location: return "location"
        case .display: return "eye"
        case .alerts: return "bell"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedTab: SettingsTab = .sources

    var body: some View {
        TabView(selection: $selectedTab) {
            SourcesSettingsView(settings: settings)
                .tabItem {
                    Label(SettingsTab.sources.rawValue, systemImage: SettingsTab.sources.icon)
                }
                .tag(SettingsTab.sources)

            LocationSettingsView(settings: settings)
                .tabItem {
                    Label(SettingsTab.location.rawValue, systemImage: SettingsTab.location.icon)
                }
                .tag(SettingsTab.location)

            DisplaySettingsView(settings: settings)
                .tabItem {
                    Label(SettingsTab.display.rawValue, systemImage: SettingsTab.display.icon)
                }
                .tag(SettingsTab.display)

            AlertsSettingsView()
                .tabItem {
                    Label(SettingsTab.alerts.rawValue, systemImage: SettingsTab.alerts.icon)
                }
                .tag(SettingsTab.alerts)
        }
        .frame(width: 500, height: 400)
    }
}

#Preview {
    SettingsView()
}
