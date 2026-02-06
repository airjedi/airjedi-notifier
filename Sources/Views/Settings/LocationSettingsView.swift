import SwiftUI

struct LocationSettingsView: View {
    @ObservedObject var settings: SettingsManager
    @StateObject private var locationService = LocationService.shared
    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""

    var body: some View {
        Form {
            Section("Reference Location") {
                TextField("Location Name", text: $settings.locationName)

                HStack {
                    Text("Latitude")
                        .frame(width: 80, alignment: .leading)
                    TextField("Latitude", text: $latitudeText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: latitudeText) { newValue in
                            if let lat = Double(newValue) {
                                settings.refLatitude = lat
                            }
                        }
                }

                HStack {
                    Text("Longitude")
                        .frame(width: 80, alignment: .leading)
                    TextField("Longitude", text: $longitudeText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: longitudeText) { newValue in
                            if let lon = Double(newValue) {
                                settings.refLongitude = lon
                            }
                        }
                }

                HStack {
                    Button(action: useCurrentLocation) {
                        HStack {
                            if locationService.isLocating {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "location.fill")
                            }
                            Text("Use Current Location")
                        }
                    }
                    .disabled(locationService.isLocating)

                    Spacer()

                    if let error = locationService.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Section("Current Setting") {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading) {
                        Text(settings.locationName.isEmpty ? "Reference Point" : settings.locationName)
                            .fontWeight(.medium)
                        Text(String(format: "%.4f, %.4f", settings.refLatitude, settings.refLongitude))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            latitudeText = String(format: "%.6f", settings.refLatitude)
            longitudeText = String(format: "%.6f", settings.refLongitude)
        }
    }

    private func useCurrentLocation() {
        Task {
            do {
                let location = try await locationService.requestCurrentLocation()
                await MainActor.run {
                    settings.refLatitude = location.coordinate.latitude
                    settings.refLongitude = location.coordinate.longitude
                    latitudeText = String(format: "%.6f", location.coordinate.latitude)
                    longitudeText = String(format: "%.6f", location.coordinate.longitude)
                    settings.locationName = "Current Location"
                }
            } catch {
                // Error is already set in locationService
            }
        }
    }
}

#Preview {
    LocationSettingsView(settings: SettingsManager.shared)
        .frame(width: 450, height: 300)
}
