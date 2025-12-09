# Settings Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a Settings window with tabs for configuring ADS-B sources, location, and display preferences, persisted via UserDefaults.

**Architecture:** SettingsManager singleton using @AppStorage for persistence. Tabbed SwiftUI Settings window. SourceConfig model for multiple ADS-B sources with priority ordering.

**Tech Stack:** Swift 5.9+, SwiftUI, @AppStorage, Codable

---

## Task 1: Create SourceConfig Model

**Files:**
- Create: `AirJedi/AirJedi/Models/SourceConfig.swift`

**Step 1: Create the SourceConfig model**

Create file `AirJedi/AirJedi/Models/SourceConfig.swift`:

```swift
import Foundation

enum SourceType: String, Codable, CaseIterable, Identifiable {
    case dump1090 = "dump1090"
    case beast = "beast"
    case sbs = "sbs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dump1090: return "dump1090 / readsb"
        case .beast: return "Beast (AVR)"
        case .sbs: return "SBS BaseStation"
        }
    }

    var defaultPort: Int {
        switch self {
        case .dump1090: return 8080
        case .beast: return 30005
        case .sbs: return 30003
        }
    }

    var protocolDescription: String {
        switch self {
        case .dump1090: return "HTTP JSON"
        case .beast: return "TCP Binary"
        case .sbs: return "TCP Text"
        }
    }
}

struct SourceConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: SourceType
    var host: String
    var port: Int
    var isEnabled: Bool
    var priority: Int

    init(
        id: UUID = UUID(),
        name: String = "New Source",
        type: SourceType = .dump1090,
        host: String = "localhost",
        port: Int? = nil,
        isEnabled: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host
        self.port = port ?? type.defaultPort
        self.isEnabled = isEnabled
        self.priority = priority
    }

    var urlString: String {
        switch type {
        case .dump1090:
            return "http://\(host):\(port)/data/aircraft.json"
        case .beast, .sbs:
            return "\(host):\(port)"
        }
    }
}
```

**Step 2: Regenerate Xcode project and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Models/SourceConfig.swift
git commit -m "Add SourceConfig model for ADS-B sources"
```

---

## Task 2: Create SettingsManager

**Files:**
- Create: `AirJedi/AirJedi/App/SettingsManager.swift`

**Step 1: Create the SettingsManager**

Create file `AirJedi/AirJedi/App/SettingsManager.swift`:

```swift
import SwiftUI
import Combine

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // MARK: - Sources

    @AppStorage("sourcesData") private var sourcesData: Data = Data()

    var sources: [SourceConfig] {
        get {
            guard !sourcesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([SourceConfig].self, from: sourcesData)) ?? []
        }
        set {
            sourcesData = (try? JSONEncoder().encode(newValue)) ?? Data()
            objectWillChange.send()
        }
    }

    func addSource(_ source: SourceConfig) {
        var current = sources
        current.append(source)
        sources = current
    }

    func updateSource(_ source: SourceConfig) {
        var current = sources
        if let index = current.firstIndex(where: { $0.id == source.id }) {
            current[index] = source
            sources = current
        }
    }

    func deleteSource(id: UUID) {
        var current = sources
        current.removeAll { $0.id == id }
        sources = current
    }

    func moveSource(from: IndexSet, to: Int) {
        var current = sources
        current.move(fromOffsets: from, toOffset: to)
        // Update priorities based on new order
        for (index, var source) in current.enumerated() {
            source.priority = index
            current[index] = source
        }
        sources = current
    }

    // MARK: - Location

    @AppStorage("refLatitude") var refLatitude: Double = 37.7749
    @AppStorage("refLongitude") var refLongitude: Double = -122.4194
    @AppStorage("locationName") var locationName: String = "San Francisco"

    var referenceLocation: Coordinate {
        Coordinate(latitude: refLatitude, longitude: refLongitude)
    }

    func setLocation(latitude: Double, longitude: Double, name: String = "") {
        refLatitude = latitude
        refLongitude = longitude
        locationName = name
        objectWillChange.send()
    }

    // MARK: - Display

    @AppStorage("refreshInterval") var refreshInterval: Double = 5.0
    @AppStorage("maxAircraftDisplay") var maxAircraftDisplay: Int = 25
    @AppStorage("staleThresholdSeconds") var staleThresholdSeconds: Int = 60
    @AppStorage("showAircraftWithoutPosition") var showAircraftWithoutPosition: Bool = false

    // MARK: - Init

    private init() {}
}
```

**Step 2: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/App/SettingsManager.swift
git commit -m "Add SettingsManager with sources, location, and display settings"
```

---

## Task 3: Create Settings Window Shell

**Files:**
- Create: `AirJedi/AirJedi/Views/Settings/SettingsView.swift`

**Step 1: Create the SettingsView with tabs**

Create directory and file `AirJedi/AirJedi/Views/Settings/SettingsView.swift`:

```swift
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

            AlertsSettingsPlaceholder()
                .tabItem {
                    Label(SettingsTab.alerts.rawValue, systemImage: SettingsTab.alerts.icon)
                }
                .tag(SettingsTab.alerts)
        }
        .frame(width: 500, height: 400)
    }
}

// Placeholder for alerts (implemented later)
struct AlertsSettingsPlaceholder: View {
    var body: some View {
        VStack {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Alerts coming soon")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
```

**Step 2: Create placeholder views (will be replaced in next tasks)**

Create file `AirJedi/AirJedi/Views/Settings/SourcesSettingsView.swift`:

```swift
import SwiftUI

struct SourcesSettingsView: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Text("Sources settings placeholder")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Create file `AirJedi/AirJedi/Views/Settings/LocationSettingsView.swift`:

```swift
import SwiftUI

struct LocationSettingsView: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Text("Location settings placeholder")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Create file `AirJedi/AirJedi/Views/Settings/DisplaySettingsView.swift`:

```swift
import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Text("Display settings placeholder")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

**Step 3: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 4: Commit**

```bash
git add AirJedi/AirJedi/Views/Settings/
git commit -m "Add Settings window shell with tab navigation"
```

---

## Task 4: Implement Sources Settings Tab

**Files:**
- Modify: `AirJedi/AirJedi/Views/Settings/SourcesSettingsView.swift`

**Step 1: Replace SourcesSettingsView with full implementation**

Replace contents of `AirJedi/AirJedi/Views/Settings/SourcesSettingsView.swift`:

```swift
import SwiftUI

struct SourcesSettingsView: View {
    @ObservedObject var settings: SettingsManager
    @State private var selectedSourceId: UUID?
    @State private var showingAddSheet = false
    @State private var editingSource: SourceConfig?

    var body: some View {
        HSplitView {
            // Source list
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedSourceId) {
                    ForEach(settings.sources) { source in
                        SourceRowView(source: source)
                            .tag(source.id)
                    }
                    .onMove { from, to in
                        settings.moveSource(from: from, to: to)
                    }
                }
                .listStyle(.bordered)

                // Add/Remove buttons
                HStack {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedSourceId == nil)
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 200, maxWidth: 250)

            // Detail view
            if let sourceId = selectedSourceId,
               let source = settings.sources.first(where: { $0.id == sourceId }) {
                SourceDetailView(source: source, settings: settings)
            } else {
                VStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a source or add a new one")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSourceSheet(settings: settings, isPresented: $showingAddSheet)
        }
    }

    private func deleteSelected() {
        if let id = selectedSourceId {
            settings.deleteSource(id: id)
            selectedSourceId = nil
        }
    }
}

struct SourceRowView: View {
    let source: SourceConfig

    var body: some View {
        HStack {
            Image(systemName: source.isEnabled ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .foregroundColor(source.isEnabled ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(source.name)
                    .fontWeight(.medium)
                Text(source.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SourceDetailView: View {
    let source: SourceConfig
    @ObservedObject var settings: SettingsManager
    @State private var editedSource: SourceConfig

    init(source: SourceConfig, settings: SettingsManager) {
        self.source = source
        self.settings = settings
        self._editedSource = State(initialValue: source)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $editedSource.name)
                Picker("Type", selection: $editedSource.type) {
                    ForEach(SourceType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                TextField("Host", text: $editedSource.host)
                TextField("Port", value: $editedSource.port, format: .number)
                Toggle("Enabled", isOn: $editedSource.isEnabled)
            }

            Section {
                HStack {
                    Text("Connection URL:")
                        .foregroundColor(.secondary)
                    Text(editedSource.urlString)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: editedSource) { _, newValue in
            settings.updateSource(newValue)
        }
        .onChange(of: source) { _, newValue in
            editedSource = newValue
        }
    }
}

struct AddSourceSheet: View {
    @ObservedObject var settings: SettingsManager
    @Binding var isPresented: Bool
    @State private var name = "New Source"
    @State private var type: SourceType = .dump1090
    @State private var host = "localhost"
    @State private var port = 8080

    var body: some View {
        VStack(spacing: 16) {
            Text("Add ADS-B Source")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $type) {
                    ForEach(SourceType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: type) { _, newType in
                    port = newType.defaultPort
                }
                TextField("Host", text: $host)
                TextField("Port", value: $port, format: .number)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Add") {
                    let newSource = SourceConfig(
                        name: name,
                        type: type,
                        host: host,
                        port: port,
                        priority: settings.sources.count
                    )
                    settings.addSource(newSource)
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350, height: 280)
    }
}

#Preview {
    SourcesSettingsView(settings: SettingsManager.shared)
        .frame(width: 500, height: 350)
}
```

**Step 2: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Views/Settings/SourcesSettingsView.swift
git commit -m "Implement Sources settings tab with add/edit/delete"
```

---

## Task 5: Implement Location Settings Tab

**Files:**
- Modify: `AirJedi/AirJedi/Views/Settings/LocationSettingsView.swift`
- Create: `AirJedi/AirJedi/Services/LocationService.swift`

**Step 1: Create LocationService for Core Location**

Create file `AirJedi/AirJedi/Services/LocationService.swift`:

```swift
import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocating = false
    @Published var error: String?

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestCurrentLocation() async throws -> CLLocation {
        isLocating = true
        error = nil

        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation

            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            } else if locationManager.authorizationStatus == .authorized {
                locationManager.requestLocation()
            } else {
                continuation.resume(throwing: LocationError.notAuthorized)
                self.locationContinuation = nil
                self.isLocating = false
            }
        }
    }

    enum LocationError: LocalizedError {
        case notAuthorized
        case locationUnavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Location access not authorized"
            case .locationUnavailable: return "Unable to determine location"
            }
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isLocating = false
        if let location = locations.last {
            lastLocation = location
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        self.error = error.localizedDescription
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorized && locationContinuation != nil {
            manager.requestLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            locationContinuation?.resume(throwing: LocationError.notAuthorized)
            locationContinuation = nil
            isLocating = false
        }
    }
}
```

**Step 2: Replace LocationSettingsView**

Replace contents of `AirJedi/AirJedi/Views/Settings/LocationSettingsView.swift`:

```swift
import SwiftUI
import CoreLocation

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
                        .onChange(of: latitudeText) { _, newValue in
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
                        .onChange(of: longitudeText) { _, newValue in
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
```

**Step 3: Add Location Usage Description to Info.plist**

Modify `AirJedi/AirJedi/Info.plist` to add:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>AirJedi uses your location to calculate distance to nearby aircraft.</string>
```

**Step 4: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 5: Commit**

```bash
git add AirJedi/AirJedi/Services/LocationService.swift
git add AirJedi/AirJedi/Views/Settings/LocationSettingsView.swift
git add AirJedi/AirJedi/Info.plist
git commit -m "Implement Location settings tab with Core Location support"
```

---

## Task 6: Implement Display Settings Tab

**Files:**
- Modify: `AirJedi/AirJedi/Views/Settings/DisplaySettingsView.swift`

**Step 1: Replace DisplaySettingsView**

Replace contents of `AirJedi/AirJedi/Views/Settings/DisplaySettingsView.swift`:

```swift
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
```

**Step 2: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Views/Settings/DisplaySettingsView.swift
git commit -m "Implement Display settings tab with refresh and display options"
```

---

## Task 7: Wire Settings to App

**Files:**
- Modify: `AirJedi/AirJedi/AirJediApp.swift`
- Modify: `AirJedi/AirJedi/App/AppState.swift`
- Modify: `AirJedi/AirJedi/Views/AircraftListView.swift`

**Step 1: Update AirJediApp to add Settings window**

Replace contents of `AirJedi/AirJedi/AirJediApp.swift`:

```swift
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
```

**Step 2: Update AppState to use SettingsManager for reference location**

Replace contents of `AirJedi/AirJedi/App/AppState.swift`:

```swift
import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var aircraft: [Aircraft] = []

    private let settings = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    var nearbyCount: Int {
        aircraft.count
    }

    var referenceLocation: Coordinate {
        settings.referenceLocation
    }

    init() {
        // Load placeholder data for development
        loadPlaceholderData()

        // Observe settings changes
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func loadPlaceholderData() {
        aircraft = [
            Aircraft(
                icaoHex: "A12345",
                callsign: "UAL123",
                position: Coordinate(latitude: 37.8, longitude: -122.4),
                altitudeFeet: 12400,
                headingDegrees: 280,
                speedKnots: 452,
                verticalRateFpm: 0,
                squawk: "1200",
                lastSeen: Date(),
                registration: "N12345",
                aircraftTypeCode: "B738",
                operatorName: "United Airlines"
            ),
            Aircraft(
                icaoHex: "A67890",
                callsign: "N456AB",
                position: Coordinate(latitude: 37.75, longitude: -122.45),
                altitudeFeet: 2800,
                headingDegrees: 145,
                speedKnots: 98,
                verticalRateFpm: -500,
                squawk: "1200",
                lastSeen: Date(),
                registration: "N456AB",
                aircraftTypeCode: "C172",
                operatorName: nil
            ),
            Aircraft(
                icaoHex: "AE1234",
                callsign: "EVAC01",
                position: Coordinate(latitude: 37.79, longitude: -122.39),
                altitudeFeet: 1500,
                headingDegrees: 90,
                speedKnots: 120,
                verticalRateFpm: 0,
                squawk: "1200",
                lastSeen: Date(),
                registration: "N789MH",
                aircraftTypeCode: "EC35",
                operatorName: "REACH Air Medical"
            )
        ]
    }
}
```

**Step 3: Update AircraftListView to add Settings button**

Modify `AirJedi/AirJedi/Views/AircraftListView.swift` - add a Settings button before Quit:

Replace contents of `AirJedi/AirJedi/Views/AircraftListView.swift`:

```swift
import SwiftUI

struct AircraftListView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    private var sortedAircraft: [Aircraft] {
        let ref = appState.referenceLocation
        return appState.aircraft.sorted { a, b in
            let distA = a.distance(from: ref) ?? .infinity
            let distB = b.distance(from: ref) ?? .infinity
            return distA < distB
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.aircraft.isEmpty {
                Text("No aircraft detected")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(sortedAircraft) { aircraft in
                    AircraftRowView(
                        aircraft: aircraft,
                        referenceLocation: appState.referenceLocation
                    )

                    if aircraft.id != sortedAircraft.last?.id {
                        Divider()
                            .padding(.horizontal, 8)
                    }
                }
            }

            Divider()

            HStack {
                Text("\(appState.nearbyCount) aircraft tracked")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            Button("Settings...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            Button("Quit AirJedi") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 300)
    }
}

#Preview {
    let appState = AppState()
    return AircraftListView(appState: appState)
}
```

**Step 4: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 5: Commit**

```bash
git add AirJedi/AirJedi/AirJediApp.swift
git add AirJedi/AirJedi/App/AppState.swift
git add AirJedi/AirJedi/Views/AircraftListView.swift
git commit -m "Wire Settings window to app with Settings menu item"
```

---

## Summary

After completing all tasks, you will have:
- SourceConfig model for configuring multiple ADS-B sources
- SettingsManager singleton with UserDefaults persistence
- Tabbed Settings window (Sources, Location, Display, Alerts placeholder)
- Sources tab with add/edit/delete and reordering
- Location tab with manual entry and "Use Current Location"
- Display tab with refresh interval and display options
- Settings accessible via menu bar dropdown

The infrastructure is ready for adding real ADS-B providers in the next increment.
