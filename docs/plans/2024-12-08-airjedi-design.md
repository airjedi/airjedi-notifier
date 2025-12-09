# AirJedi Notifier - Design Document

A macOS menu bar application for monitoring nearby aircraft via ADS-B feeds.

## Overview

AirJedi displays real-time aircraft data from ADS-B receivers in the macOS menu bar. It shows rich details (callsign, type, altitude, distance, heading, speed, route) and provides configurable notifications for interesting aircraft, proximity alerts, and emergency squawks.

## Architecture

Layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────┐
│           UI Layer (SwiftUI)            │
│  MenuBarExtra, Views, ViewModels        │
├─────────────────────────────────────────┤
│           Domain Layer                  │
│  Aircraft, Alert Rules, Notifications   │
├─────────────────────────────────────────┤
│          Service Layer                  │
│  AircraftService, AlertEngine,          │
│  LocationService, EnrichmentService     │
├─────────────────────────────────────────┤
│          Provider Layer                 │
│  ADSBProvider (protocol)                │
│  └─ Dump1090, Beast, SBS, API impls     │
│  LocationProvider (protocol)            │
│  └─ ReceiverGPS, CoreLocation, Fixed    │
└─────────────────────────────────────────┘
```

**Key abstractions:**
- **ADSBProvider** - Protocol for any data source. Implementations handle parsing; all emit unified Aircraft models
- **LocationProvider** - Protocol for position. Receiver GPS primary, fixed coordinates fallback
- **AlertRule** - Protocol for notification triggers. Composable rules that evaluate aircraft state

## Core Data Models

```swift
struct Aircraft: Identifiable {
    let icaoHex: String           // 24-bit ICAO address (unique ID)
    var callsign: String?         // Flight number or registration
    var position: Coordinate?     // Lat/lon if known
    var altitude: Altitude?       // Barometric or geometric
    var heading: Double?          // Track angle in degrees
    var speed: Speed?             // Ground speed
    var verticalRate: Double?     // Feet per minute
    var squawk: String?           // Transponder code
    var lastSeen: Date            // For staleness detection

    // Enriched data (populated by EnrichmentService)
    var registration: String?     // N-number, G-reg, etc.
    var aircraftType: AircraftType?
    var operator: String?
    var route: Route?             // Origin/destination
}

struct AircraftType {
    let icaoCode: String          // e.g., "B738"
    let manufacturer: String      // e.g., "Boeing"
    let model: String             // e.g., "737-800"
    let category: Category        // .airliner, .military, .helicopter, etc.
}

struct Route {
    let origin: Airport?
    let destination: Airport?
}
```

**Design notes:**
- `icaoHex` is the stable identifier - callsigns can change mid-flight
- Most fields are optional since ADS-B messages arrive incrementally
- Enrichment data is separated from raw ADS-B to keep provider layer pure
- `lastSeen` enables cleanup of stale aircraft (no message in X seconds)

## Provider Abstraction

```swift
protocol ADSBProvider {
    var id: String { get }
    var displayName: String { get }
    var status: ProviderStatus { get }

    var aircraftUpdates: AsyncStream<AircraftUpdate> { get }

    func connect() async throws
    func disconnect() async
}

enum ProviderStatus {
    case disconnected
    case connecting
    case connected(aircraftCount: Int)
    case error(Error)
}

enum AircraftUpdate {
    case updated(Aircraft)        // New or changed aircraft
    case removed(String)          // icaoHex of aircraft gone stale
    case snapshot([Aircraft])     // Full state (for HTTP polling sources)
}

protocol LocationProvider {
    var currentLocation: Coordinate? { get }
    var locationUpdates: AsyncStream<Coordinate> { get }
    func start() async throws
    func stop() async
}
```

**Implementation strategy:**
- **Dump1090/Readsb**: HTTP polling of `aircraft.json`, emits `.snapshot`
- **Beast/RAW**: TCP socket with binary parsing, emits `.updated`
- **SBS BaseStation**: TCP socket with line-based parsing, emits `.updated`
- **APIs**: HTTP polling with rate limiting, emits `.snapshot`

## Alert Rules Engine

```swift
protocol AlertRule: Identifiable {
    var id: UUID { get }
    var name: String { get }
    var isEnabled: Bool { get set }

    func evaluate(_ aircraft: Aircraft, context: AlertContext) -> AlertResult?
}

struct AlertContext {
    let myLocation: Coordinate
    let allAircraft: [Aircraft]
    let previousStates: [String: Aircraft]
}

enum AlertResult {
    case notify(title: String, body: String, priority: Priority)
    case silent(reason: String)
}
```

**Built-in rule types:**
- `ProximityRule` - Within X nm and Y feet
- `WatchlistRule` - Specific registrations/callsigns
- `AircraftTypeRule` - Military, helicopters, etc.
- `SquawkRule` - 7500, 7600, 7700 emergencies
- `PatternRule` - Circling, rapid descent, etc.

**AlertEngine responsibilities:**
- Evaluates all enabled rules against each aircraft update
- Manages cooldowns (don't spam for same aircraft)
- Coalesces multiple triggers into single notification
- Persists rule configuration

## UI Design

**Menu bar icon states:**
- Idle: Simple airplane outline
- Active: Airplane with badge showing nearby aircraft count
- Alert: Airplane with accent color when interesting aircraft detected
- Disconnected: Grayed out airplane with indicator

**Dropdown content:**
```
┌──────────────────────────────────────┐
│  ✈ UAL123  B738   12,400ft   3.2nm  │
│    → SFO-LAX   ↗ 280°  452kt        │
├──────────────────────────────────────┤
│  ✈ N456AB  C172    2,800ft   1.1nm  │
│    ↗ 145°  98kt                      │
├──────────────────────────────────────┤
│  7 aircraft tracked                  │
│  ─────────────────────────────────── │
│  Settings...              ⌘,         │
│  Quit AirJedi             ⌘Q         │
└──────────────────────────────────────┘
```

**Adaptive refresh:**
- Menu closed: Poll every 10 seconds, process alerts
- Menu open: Refresh every 1-2 seconds for live feel

## Service Layer

```swift
class AppState: ObservableObject {
    @Published var aircraft: [Aircraft] = []
    @Published var nearbyCount: Int = 0
    @Published var providerStatus: ProviderStatus = .disconnected

    private let aircraftService: AircraftService
    private let alertEngine: AlertEngine
    private let enrichmentService: EnrichmentService
    private let locationService: LocationService
}

class AircraftService {
    // Merges updates from all providers
    // Handles deduplication
    // Removes stale aircraft (no update in 60 seconds)
}

class EnrichmentService {
    // Looks up registration, type, operator
    // Local database + optional API calls
    // Caches results
}

class LocationService {
    // Priority: ReceiverGPS > CoreLocation > FixedLocation
    // Automatic fallback
}
```

**Data flow:**
1. ADSBProvider emits raw aircraft updates
2. AircraftService merges, dedupes, manages staleness
3. EnrichmentService decorates with type/registration/route
4. AlertEngine evaluates rules, triggers notifications
5. AppState publishes to SwiftUI views

## Project Structure

```
AirJedi/
├── App/
│   ├── AirJediApp.swift
│   └── AppState.swift
├── Models/
│   ├── Aircraft.swift
│   ├── AircraftType.swift
│   ├── Coordinate.swift
│   └── AlertRule.swift
├── Providers/
│   ├── ADSBProvider.swift
│   ├── LocationProvider.swift
│   └── Implementations/
├── Services/
│   ├── AircraftService.swift
│   ├── AlertEngine.swift
│   ├── EnrichmentService.swift
│   └── LocationService.swift
├── Views/
│   ├── MenuBarIcon.swift
│   ├── AircraftListView.swift
│   ├── AircraftRowView.swift
│   └── SettingsView.swift
└── Resources/
    └── Assets.xcassets
```

## Technology Choices

- **Swift + SwiftUI** for native macOS integration
- **MenuBarExtra** for menu bar presence
- **Async/await + AsyncStream** for data flow
- **Combine** for UI state binding
- **UserDefaults** for settings persistence

## Initial Build Scope

For the first iteration, implement only:
1. Basic MenuBarExtra with airplane SF Symbol icon
2. Skeleton AppState with placeholder data
3. MenuBarIcon view
4. Xcode project configured as menu bar app (no dock icon)

This provides the visible shell to build upon incrementally.
