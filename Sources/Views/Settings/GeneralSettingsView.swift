import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @State private var launchAtLogin: Bool = false
    @State private var showInstallAlert: Bool = false

    private var isInstalledInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications")
    }

    var body: some View {
        Form {
            Section("Startup") {
                if isInstalledInApplications {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(enabled: newValue)
                        }
                } else {
                    HStack {
                        Toggle("Launch at Login", isOn: .constant(false))
                            .disabled(true)
                        Spacer()
                        Button("Why?") {
                            showInstallAlert = true
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            if !isInstalledInApplications {
                Section {
                    Label {
                        Text("Move AirJedi to your Applications folder to enable Launch at Login.")
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Build")
                    Spacer()
                    Text(buildNumber)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = currentLaunchAtLoginStatus()
        }
        .alert("Installation Required", isPresented: $showInstallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To enable Launch at Login, please move AirJedi.app to your Applications folder. This ensures the setting persists across app updates.")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private func currentLaunchAtLoginStatus() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            // Revert the toggle state on failure
            launchAtLogin = currentLaunchAtLoginStatus()
        }
    }
}

#Preview {
    GeneralSettingsView()
        .frame(width: 450, height: 300)
}
