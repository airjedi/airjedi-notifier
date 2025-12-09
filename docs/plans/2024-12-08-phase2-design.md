# AirJedi Phase 2 - Settings, Providers, and Alerts Design

## Overview

Add real ADS-B data connectivity, configurable settings, and a notification system for aircraft alerts. This phase transforms AirJedi from a placeholder demo into a functional aircraft monitoring tool.

## Features

1. **Settings Window** - Tabbed interface for configuring sources, location, display, and alerts
2. **ADS-B Providers** - Multiple source types (dump1090, Beast, SBS) with priority/fallback
3. **Alert Engine** - Notifications for proximity, watchlist, squawks, and aircraft types

## Settings Architecture

### SettingsManager

Central settings coordinator using UserDefaults:

```swift
@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // Sources (multiple with priority)
    @AppStorage("sources") var sourcesData: Data = Data()
    var sources: [SourceConfig] { get/set }

    // Location
    @AppStorage("refLatitude") var refLatitude: Double = 0
    @AppStorage("refLongitude") var refLongitude: Double = 0

    // Display
    @AppStorage("refreshInterval") var refreshInterval: Double = 5.0
    @AppStorage("maxAircraftDisplay") var maxAircraftDisplay: Int = 20
    @AppStorage("staleThresholdSeconds") var staleThreshold: Int = 60

    // Alerts (stored as encoded data)
    @AppStorage("alertRulesData") var alertRulesData: Data = Data()
}
```

### SourceConfig

Configuration for each ADS-B source:

```swift
struct SourceConfig: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: SourceType  // .dump1090, .beast, .sbs
    var host: String
    var port: Int
    var isEnabled: Bool
    var priority: Int     // Lower = higher priority
}

enum SourceType: String, Codable, CaseIterable {
    case dump1090 = "dump1090"
    case beast = "beast"
    case sbs = "sbs"

    var defaultPort: Int {
        switch self {
        case .dump1090: return 8080
        case .beast: return 30005
        case .sbs: return 30003
        }
    }
}
```

### Settings Window

Tabbed interface with four tabs:

```
┌─────────────────────────────────────────────────────┐
│  [Sources]  [Location]  [Display]  [Alerts]         │
├─────────────────────────────────────────────────────┤
│                                                     │
│   Tab content here                                  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

- **Sources Tab**: List of configured sources with add/edit/delete, enable/disable toggle, priority ordering
- **Location Tab**: Manual lat/lon entry plus "Use Current Location" button (one-time Core Location)
- **Display Tab**: Refresh interval, max aircraft to show, stale threshold
- **Alerts Tab**: List of alert rules with add/edit/delete, enable/disable toggle

## ADS-B Provider Architecture

### Protocol

```swift
protocol ADSBProvider: AnyObject {
    var id: UUID { get }
    var config: SourceConfig { get }
    var status: ProviderStatus { get }
    var statusPublisher: AnyPublisher<ProviderStatus, Never> { get }
    var aircraftPublisher: AnyPublisher<AircraftUpdate, Never> { get }

    func connect() async throws
    func disconnect() async
}

enum ProviderStatus: Equatable {
    case disconnected
    case connecting
    case connected(aircraftCount: Int)
    case error(String)
}

enum AircraftUpdate {
    case updated(Aircraft)
    case removed(String)  // icaoHex
    case snapshot([Aircraft])
}
```

### Implementations

| Provider | Protocol | Parsing | Update Style |
|----------|----------|---------|--------------|
| Dump1090Provider | HTTP GET /aircraft.json | JSON | Polling → .snapshot |
| BeastProvider | TCP port 30005 | Binary AVR frames | Streaming → .updated |
| SBSProvider | TCP port 30003 | CSV-like lines | Streaming → .updated |

### ProviderManager

Coordinates multiple sources:

```swift
@MainActor
class ProviderManager: ObservableObject {
    @Published var providers: [any ADSBProvider] = []
    @Published var combinedStatus: ProviderStatus = .disconnected

    private let aircraftService: AircraftService

    func startAll() async
    func stopAll() async
    func addProvider(config: SourceConfig)
    func removeProvider(id: UUID)
}
```

### AircraftService

Merges updates from all providers:

```swift
@MainActor
class AircraftService: ObservableObject {
    @Published var aircraft: [Aircraft] = []

    private var aircraftCache: [String: Aircraft] = [:]  // icaoHex -> Aircraft
    private var staleThreshold: TimeInterval = 60

    func processUpdate(_ update: AircraftUpdate, from provider: UUID)
    func removeStaleAircraft()
}
```

## Alert Engine Architecture

### AlertRule Protocol

```swift
protocol AlertRule: Identifiable, Codable {
    var id: UUID { get }
    var name: String { get }
    var isEnabled: Bool { get set }

    func evaluate(_ aircraft: Aircraft, context: AlertContext) -> AlertResult?
}

struct AlertContext {
    let referenceLocation: Coordinate
    let allAircraft: [Aircraft]
    let previousStates: [String: Aircraft]
}

enum AlertResult {
    case trigger(Alert)
    case suppressed(reason: String)
}

struct Alert {
    let aircraft: Aircraft
    let rule: any AlertRule
    let title: String
    let body: String
    let priority: AlertPriority
    let sound: AlertSound?
}

enum AlertPriority: String, Codable {
    case low
    case normal
    case high
    case critical
}
```

### Built-in Rule Types

```swift
struct ProximityRule: AlertRule {
    var maxDistanceNm: Double
    var maxAltitudeFeet: Int?
    var minAltitudeFeet: Int?
}

struct WatchlistRule: AlertRule {
    var callsigns: [String]
    var registrations: [String]
    var icaoHexCodes: [String]
}

struct SquawkRule: AlertRule {
    var squawkCodes: [String]  // "7500", "7600", "7700"
}

struct AircraftTypeRule: AlertRule {
    var categories: [AircraftCategory]  // .military, .helicopter, .jet
    var typeCodes: [String]  // "C17", "F16", etc.
}
```

### AlertEngine

```swift
@MainActor
class AlertEngine: ObservableObject {
    @Published var rules: [any AlertRule] = []
    @Published var recentAlerts: [Alert] = []

    private var cooldowns: [String: Date] = [:]
    var cooldownSeconds: Int = 300  // 5 min cooldown per aircraft

    func evaluate(_ aircraft: Aircraft, context: AlertContext)
    func deliverAlert(_ alert: Alert) async
}
```

## Notification Delivery

### Multi-channel System

```swift
class NotificationManager {
    static let shared = NotificationManager()

    func requestPermission() async -> Bool
    func deliver(_ alert: Alert) async
}
```

### Channels

1. **System Notifications** - UserNotifications framework with actions
2. **Menu Bar Visual** - Icon state changes (normal, alert, disconnected)
3. **Sound Options** - Configurable alert sounds

### AlertSound

```swift
enum AlertSound: String, Codable, CaseIterable {
    case none
    case subtle
    case standard
    case prominent
    case military
    case emergency
}
```

### Priority Behavior

| Priority | System Notif | Sound | Icon Flash |
|----------|--------------|-------|------------|
| .low | Silent | None | No |
| .normal | Banner | Subtle | Brief |
| .high | Banner + Sound | Standard | Yes |
| .critical | Persistent | Emergency | Continuous |

## Project Structure

New files to add:

```
AirJedi/AirJedi/
├── App/
│   ├── AppState.swift              # Update: inject services
│   └── SettingsManager.swift       # NEW
├── Models/
│   ├── Aircraft.swift
│   ├── Coordinate.swift
│   ├── SourceConfig.swift          # NEW
│   └── AlertRules/                 # NEW
│       ├── AlertRule.swift
│       ├── ProximityRule.swift
│       ├── WatchlistRule.swift
│       ├── SquawkRule.swift
│       └── AircraftTypeRule.swift
├── Providers/                      # NEW
│   ├── ADSBProvider.swift
│   ├── ProviderManager.swift
│   ├── Dump1090Provider.swift
│   ├── BeastProvider.swift
│   └── SBSProvider.swift
├── Services/                       # NEW
│   ├── AircraftService.swift
│   ├── AlertEngine.swift
│   ├── NotificationManager.swift
│   └── LocationService.swift
├── Views/
│   ├── MenuBarIcon.swift
│   ├── AircraftListView.swift
│   ├── AircraftRowView.swift
│   └── Settings/                   # NEW
│       ├── SettingsView.swift
│       ├── SourcesSettingsView.swift
│       ├── LocationSettingsView.swift
│       ├── DisplaySettingsView.swift
│       └── AlertsSettingsView.swift
```

## Data Flow

```
SourceConfig (UserDefaults)
       ↓
ProviderManager → creates → [ADSBProvider instances]
       ↓                           ↓
       ↓                    AircraftUpdate events
       ↓                           ↓
       └──────────→ AircraftService ←──────────┘
                          ↓
                   [Aircraft] merged, deduped
                          ↓
              ┌───────────┴───────────┐
              ↓                       ↓
         AlertEngine              AppState
              ↓                       ↓
    NotificationManager          SwiftUI Views
```

## Implementation Order

1. **Settings Infrastructure** - SettingsManager, SourceConfig, Settings window shell
2. **Provider Protocol & Dump1090** - Get real data flowing first
3. **AircraftService** - Merge/dedupe/staleness management
4. **Beast & SBS Providers** - Additional source types
5. **Alert Rules & Engine** - Core alert logic
6. **Notification Delivery** - System notifications, sounds, visual feedback
7. **Settings UI Completion** - All tabs fully functional
