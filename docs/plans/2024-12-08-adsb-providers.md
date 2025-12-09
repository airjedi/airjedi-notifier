# ADS-B Providers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the ADSBProvider protocol and Dump1090Provider to connect to real ADS-B data sources, replacing placeholder data with live aircraft.

**Architecture:** Protocol-based provider system with async streams. ProviderManager coordinates multiple sources. AircraftService merges updates, handles deduplication and staleness.

**Tech Stack:** Swift 5.9+, async/await, Combine, URLSession, AsyncStream

---

## Task 1: Create ADSBProvider Protocol

**Files:**
- Create: `AirJedi/AirJedi/Providers/ADSBProvider.swift`

**Step 1: Create the protocol and supporting types**

Create directory and file `AirJedi/AirJedi/Providers/ADSBProvider.swift`:

```swift
import Foundation
import Combine

// MARK: - Provider Status

enum ProviderStatus: Equatable {
    case disconnected
    case connecting
    case connected(aircraftCount: Int)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected(let count): return "Connected (\(count) aircraft)"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Aircraft Update

enum AircraftUpdate {
    case updated(Aircraft)
    case removed(String)  // icaoHex of aircraft to remove
    case snapshot([Aircraft])  // Full state replacement
}

// MARK: - Provider Protocol

protocol ADSBProvider: AnyObject, Identifiable {
    var id: UUID { get }
    var config: SourceConfig { get }
    var status: ProviderStatus { get }
    var statusPublisher: AnyPublisher<ProviderStatus, Never> { get }
    var aircraftPublisher: AnyPublisher<AircraftUpdate, Never> { get }

    func connect() async
    func disconnect() async
}

// MARK: - Provider Factory

enum ProviderFactory {
    static func createProvider(for config: SourceConfig) -> any ADSBProvider {
        switch config.type {
        case .dump1090:
            return Dump1090Provider(config: config)
        case .beast:
            // TODO: Implement BeastProvider
            fatalError("Beast provider not yet implemented")
        case .sbs:
            // TODO: Implement SBSProvider
            fatalError("SBS provider not yet implemented")
        }
    }
}
```

**Step 2: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds (Dump1090Provider referenced but will be created next).

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Providers/
git commit -m "Add ADSBProvider protocol and supporting types"
```

---

## Task 2: Create Dump1090Provider

**Files:**
- Create: `AirJedi/AirJedi/Providers/Dump1090Provider.swift`

**Step 1: Create the Dump1090 JSON response models**

Create file `AirJedi/AirJedi/Providers/Dump1090Provider.swift`:

```swift
import Foundation
import Combine

// MARK: - Dump1090 JSON Models

struct Dump1090Response: Codable {
    let now: Double?
    let messages: Int?
    let aircraft: [Dump1090Aircraft]
}

struct Dump1090Aircraft: Codable {
    let hex: String
    let flight: String?
    let lat: Double?
    let lon: Double?
    let altBaro: IntOrString?
    let altGeom: Int?
    let gs: Double?
    let track: Double?
    let baroRate: Int?
    let squawk: String?
    let category: String?
    let seen: Double?
    let rssi: Double?

    enum CodingKeys: String, CodingKey {
        case hex, flight, lat, lon, gs, track, squawk, category, seen, rssi
        case altBaro = "alt_baro"
        case altGeom = "alt_geom"
        case baroRate = "baro_rate"
    }
}

// Handle altitude that can be Int or String ("ground")
enum IntOrString: Codable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(IntOrString.self, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected Int or String"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let val): try container.encode(val)
        case .string(let val): try container.encode(val)
        }
    }

    var intValue: Int? {
        if case .int(let val) = self { return val }
        return nil
    }
}

// MARK: - Dump1090 Provider

class Dump1090Provider: ADSBProvider, ObservableObject {
    let id: UUID
    let config: SourceConfig

    @Published private(set) var status: ProviderStatus = .disconnected

    var statusPublisher: AnyPublisher<ProviderStatus, Never> {
        $status.eraseToAnyPublisher()
    }

    private let aircraftSubject = PassthroughSubject<AircraftUpdate, Never>()
    var aircraftPublisher: AnyPublisher<AircraftUpdate, Never> {
        aircraftSubject.eraseToAnyPublisher()
    }

    private var pollingTask: Task<Void, Never>?
    private var isRunning = false

    init(config: SourceConfig) {
        self.id = config.id
        self.config = config
    }

    func connect() async {
        guard !isRunning else { return }
        isRunning = true

        await MainActor.run {
            status = .connecting
        }

        pollingTask = Task { [weak self] in
            guard let self = self else { return }
            await self.pollLoop()
        }
    }

    func disconnect() async {
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil

        await MainActor.run {
            status = .disconnected
        }
    }

    private func pollLoop() async {
        let refreshInterval = SettingsManager.shared.refreshInterval

        while isRunning && !Task.isCancelled {
            await fetchAircraft()

            try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
        }
    }

    private func fetchAircraft() async {
        let urlString = config.urlString
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                status = .error("Invalid URL: \(urlString)")
            }
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    status = .error("Invalid response")
                }
                return
            }

            guard httpResponse.statusCode == 200 else {
                await MainActor.run {
                    status = .error("HTTP \(httpResponse.statusCode)")
                }
                return
            }

            let decoder = JSONDecoder()
            let dump1090Response = try decoder.decode(Dump1090Response.self, from: data)

            let aircraft = dump1090Response.aircraft.compactMap { convertToAircraft($0) }

            await MainActor.run {
                status = .connected(aircraftCount: aircraft.count)
            }

            aircraftSubject.send(.snapshot(aircraft))

        } catch is CancellationError {
            // Task was cancelled, ignore
        } catch {
            await MainActor.run {
                status = .error(error.localizedDescription)
            }
        }
    }

    private func convertToAircraft(_ d: Dump1090Aircraft) -> Aircraft {
        var position: Coordinate? = nil
        if let lat = d.lat, let lon = d.lon {
            position = Coordinate(latitude: lat, longitude: lon)
        }

        let altitude = d.altBaro?.intValue ?? d.altGeom

        return Aircraft(
            icaoHex: d.hex.uppercased(),
            callsign: d.flight?.trimmingCharacters(in: .whitespaces),
            position: position,
            altitudeFeet: altitude,
            headingDegrees: d.track,
            speedKnots: d.gs,
            verticalRateFpm: d.baroRate.map { Double($0) },
            squawk: d.squawk,
            lastSeen: Date(),
            registration: nil,
            aircraftTypeCode: nil,
            operatorName: nil
        )
    }
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
git add AirJedi/AirJedi/Providers/Dump1090Provider.swift
git commit -m "Add Dump1090Provider with JSON polling"
```

---

## Task 3: Create AircraftService

**Files:**
- Create: `AirJedi/AirJedi/Services/AircraftService.swift`

**Step 1: Create the AircraftService**

Create file `AirJedi/AirJedi/Services/AircraftService.swift`:

```swift
import Foundation
import Combine

@MainActor
class AircraftService: ObservableObject {
    @Published private(set) var aircraft: [Aircraft] = []
    @Published private(set) var lastUpdate: Date?

    private var aircraftCache: [String: Aircraft] = [:]  // icaoHex -> Aircraft
    private var cancellables = Set<AnyCancellable>()
    private var staleTimer: Timer?

    private let settings = SettingsManager.shared

    init() {
        startStaleTimer()
    }

    deinit {
        staleTimer?.invalidate()
    }

    // MARK: - Provider Subscription

    func subscribe(to provider: any ADSBProvider) {
        provider.aircraftPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.processUpdate(update)
            }
            .store(in: &cancellables)
    }

    func unsubscribeAll() {
        cancellables.removeAll()
    }

    // MARK: - Update Processing

    private func processUpdate(_ update: AircraftUpdate) {
        switch update {
        case .updated(let aircraft):
            aircraftCache[aircraft.icaoHex] = aircraft

        case .removed(let icaoHex):
            aircraftCache.removeValue(forKey: icaoHex)

        case .snapshot(let aircraftList):
            // Replace cache with snapshot
            var newCache: [String: Aircraft] = [:]
            for ac in aircraftList {
                newCache[ac.icaoHex] = ac
            }
            aircraftCache = newCache
        }

        updatePublishedAircraft()
    }

    private func updatePublishedAircraft() {
        let showWithoutPosition = settings.showAircraftWithoutPosition
        let maxDisplay = settings.maxAircraftDisplay
        let referenceLocation = settings.referenceLocation

        var filtered = Array(aircraftCache.values)

        // Filter out aircraft without position if setting is off
        if !showWithoutPosition {
            filtered = filtered.filter { $0.position != nil }
        }

        // Sort by distance
        filtered.sort { a, b in
            let distA = a.distance(from: referenceLocation) ?? .infinity
            let distB = b.distance(from: referenceLocation) ?? .infinity
            return distA < distB
        }

        // Limit to max display
        if filtered.count > maxDisplay && maxDisplay < 999 {
            filtered = Array(filtered.prefix(maxDisplay))
        }

        aircraft = filtered
        lastUpdate = Date()
    }

    // MARK: - Stale Aircraft Removal

    private func startStaleTimer() {
        staleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.removeStaleAircraft()
            }
        }
    }

    private func removeStaleAircraft() {
        let threshold = TimeInterval(settings.staleThresholdSeconds)
        let now = Date()

        var removedAny = false
        for (icaoHex, aircraft) in aircraftCache {
            if now.timeIntervalSince(aircraft.lastSeen) > threshold {
                aircraftCache.removeValue(forKey: icaoHex)
                removedAny = true
            }
        }

        if removedAny {
            updatePublishedAircraft()
        }
    }

    // MARK: - Manual Refresh

    func clearAll() {
        aircraftCache.removeAll()
        aircraft = []
    }
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
git add AirJedi/AirJedi/Services/AircraftService.swift
git commit -m "Add AircraftService for merging and managing aircraft data"
```

---

## Task 4: Create ProviderManager

**Files:**
- Create: `AirJedi/AirJedi/Providers/ProviderManager.swift`

**Step 1: Create the ProviderManager**

Create file `AirJedi/AirJedi/Providers/ProviderManager.swift`:

```swift
import Foundation
import Combine

@MainActor
class ProviderManager: ObservableObject {
    @Published private(set) var providers: [any ADSBProvider] = []
    @Published private(set) var combinedStatus: ProviderStatus = .disconnected

    private let settings = SettingsManager.shared
    private let aircraftService: AircraftService
    private var cancellables = Set<AnyCancellable>()
    private var statusCancellables = Set<AnyCancellable>()

    init(aircraftService: AircraftService) {
        self.aircraftService = aircraftService

        // Observe settings changes
        settings.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.syncProviders()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Provider Lifecycle

    func startAll() async {
        await syncProviders()

        for provider in providers {
            await provider.connect()
        }

        updateCombinedStatus()
    }

    func stopAll() async {
        for provider in providers {
            await provider.disconnect()
        }

        aircraftService.clearAll()
        updateCombinedStatus()
    }

    func restart() async {
        await stopAll()
        await startAll()
    }

    // MARK: - Provider Sync

    private func syncProviders() async {
        let enabledConfigs = settings.sources.filter { $0.isEnabled }
        let existingIds = Set(providers.map { $0.id })
        let configIds = Set(enabledConfigs.map { $0.id })

        // Remove providers that are no longer in config
        for provider in providers where !configIds.contains(provider.id) {
            await provider.disconnect()
        }
        providers.removeAll { !configIds.contains($0.id) }

        // Add new providers
        for config in enabledConfigs where !existingIds.contains(config.id) {
            let provider = ProviderFactory.createProvider(for: config)
            providers.append(provider)
            subscribeToProvider(provider)
        }

        updateCombinedStatus()
    }

    private func subscribeToProvider(_ provider: any ADSBProvider) {
        // Subscribe AircraftService to updates
        aircraftService.subscribe(to: provider)

        // Subscribe to status updates
        provider.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCombinedStatus()
            }
            .store(in: &statusCancellables)
    }

    // MARK: - Combined Status

    private func updateCombinedStatus() {
        if providers.isEmpty {
            combinedStatus = .disconnected
            return
        }

        var totalAircraft = 0
        var hasError = false
        var hasConnecting = false
        var hasConnected = false

        for provider in providers {
            switch provider.status {
            case .connected(let count):
                hasConnected = true
                totalAircraft += count
            case .connecting:
                hasConnecting = true
            case .error:
                hasError = true
            case .disconnected:
                break
            }
        }

        if hasConnected {
            combinedStatus = .connected(aircraftCount: totalAircraft)
        } else if hasConnecting {
            combinedStatus = .connecting
        } else if hasError {
            combinedStatus = .error("Connection failed")
        } else {
            combinedStatus = .disconnected
        }
    }
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
git add AirJedi/AirJedi/Providers/ProviderManager.swift
git commit -m "Add ProviderManager to coordinate ADS-B sources"
```

---

## Task 5: Update AppState to Use Services

**Files:**
- Modify: `AirJedi/AirJedi/App/AppState.swift`

**Step 1: Replace AppState with service-based implementation**

Replace contents of `AirJedi/AirJedi/App/AppState.swift`:

```swift
import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isConnecting = false

    let aircraftService: AircraftService
    let providerManager: ProviderManager

    private let settings = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    var aircraft: [Aircraft] {
        aircraftService.aircraft
    }

    var nearbyCount: Int {
        aircraftService.aircraft.count
    }

    var referenceLocation: Coordinate {
        settings.referenceLocation
    }

    var connectionStatus: ProviderStatus {
        providerManager.combinedStatus
    }

    init() {
        self.aircraftService = AircraftService()
        self.providerManager = ProviderManager(aircraftService: aircraftService)

        // Forward changes from services to trigger view updates
        aircraftService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        providerManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

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
git add AirJedi/AirJedi/App/AppState.swift
git commit -m "Update AppState to use AircraftService and ProviderManager"
```

---

## Task 6: Update UI to Show Connection Status

**Files:**
- Modify: `AirJedi/AirJedi/Views/AircraftListView.swift`
- Modify: `AirJedi/AirJedi/Views/MenuBarIcon.swift`

**Step 1: Update MenuBarIcon to show connection status**

Replace contents of `AirJedi/AirJedi/Views/MenuBarIcon.swift`:

```swift
import SwiftUI

struct MenuBarIcon: View {
    let aircraftCount: Int
    let status: ProviderStatus

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(iconColor)

            if aircraftCount > 0 && status.isConnected {
                Text("\(aircraftCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Circle().fill(Color.blue))
                    .offset(x: 6, y: -4)
            }
        }
    }

    private var iconName: String {
        switch status {
        case .error:
            return "airplane.circle.fill"
        case .disconnected:
            return "airplane"
        default:
            return "airplane"
        }
    }

    private var iconColor: Color? {
        switch status {
        case .error:
            return .red
        case .disconnected:
            return .secondary
        default:
            return nil
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        MenuBarIcon(aircraftCount: 0, status: .disconnected)
        MenuBarIcon(aircraftCount: 3, status: .connected(aircraftCount: 3))
        MenuBarIcon(aircraftCount: 0, status: .connecting)
        MenuBarIcon(aircraftCount: 0, status: .error("Failed"))
    }
    .padding()
}
```

**Step 2: Update AircraftListView to show status**

Replace contents of `AirJedi/AirJedi/Views/AircraftListView.swift`:

```swift
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

            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
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
```

**Step 3: Update AirJediApp to pass status to MenuBarIcon**

Replace contents of `AirJedi/AirJedi/AirJediApp.swift`:

```swift
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
                status: appState.connectionStatus
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
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
git add AirJedi/AirJedi/Views/
git add AirJedi/AirJedi/AirJediApp.swift
git commit -m "Update UI to show connection status and live aircraft data"
```

---

## Summary

After completing all tasks, you will have:
- ADSBProvider protocol for any data source type
- Dump1090Provider that polls aircraft.json and emits snapshots
- AircraftService that manages aircraft cache with staleness removal
- ProviderManager that coordinates multiple sources
- Updated AppState using real services instead of placeholder data
- UI showing connection status, refresh button, and live data

To test:
1. Add a source in Settings → Sources (e.g., localhost:8080 for dump1090)
2. Click the airplane icon to see connection status
3. Aircraft should appear if a dump1090/readsb instance is running
