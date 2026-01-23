import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Data Refresh") {
                HStack {
                    Text("Refresh Interval")
                    Spacer()
                    Picker("", selection: $settings.refreshInterval) {
                        Text("1 second").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                        Text("30 seconds").tag(30.0)
                    }
                    .frame(width: 150)
                }

                HStack {
                    Text("Stale Aircraft Timeout")
                    Spacer()
                    Picker("", selection: $settings.staleThresholdSeconds) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }
                    .frame(width: 150)
                }
            }

            Section("Aircraft Display") {
                HStack {
                    Text("Maximum Aircraft to Show")
                    Spacer()
                    Picker("", selection: $settings.maxAircraftDisplay) {
                        Text("10").tag(10)
                        Text("25").tag(25)
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("Unlimited").tag(999)
                    }
                    .frame(width: 150)
                }

                Toggle("Show Aircraft Without Position", isOn: $settings.showAircraftWithoutPosition)
            }

            Section {
                Text("Aircraft without position data are those that have been detected but haven't transmitted their GPS coordinates yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    DisplaySettingsView(settings: SettingsManager.shared)
        .frame(width: 450, height: 350)
}
