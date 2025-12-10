# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

This project uses xcodegen and a Makefile for build automation. The `.xcodeproj` is generated and not committed.

```bash
make build      # Generate project and build (Debug)
make run        # Build and launch the app
make release    # Build release configuration
make clean      # Remove build artifacts and DerivedData
make install    # Build release and copy to /Applications
make generate   # Regenerate Xcode project only
```

Install xcodegen via Homebrew: `brew install xcodegen`

## Architecture Overview

AirJedi is a macOS menu bar app (LSUIElement) that displays nearby aircraft from ADS-B receivers.

### Data Flow

```
ADS-B Receivers → Providers → AircraftService → AppState → Views
                                    ↓
                              AlertEngine → NotificationManager
```

### Key Components

**AppState** (`AirJedi/AirJedi/App/AppState.swift`): Central coordinator that owns all services and forwards Combine `objectWillChange` events to trigger SwiftUI updates.

**Providers** (`AirJedi/AirJedi/Providers/`): Protocol-based ADS-B data sources implementing `ADSBProvider`:
- `Dump1090Provider` - HTTP JSON polling (port 8080)
- `SBSProvider` - TCP text stream (port 30003, uses CRLF line endings)
- `BeastProvider` - TCP binary AVR frames (port 30005)

All providers emit `AircraftUpdate` events via Combine publishers. `ProviderManager` coordinates multiple sources and subscribes `AircraftService` to their updates.

**AircraftService** (`AirJedi/AirJedi/Services/AircraftService.swift`): Maintains aircraft cache keyed by ICAO hex, handles deduplication, staleness removal (60s default), and filtering by position/distance.

**AlertEngine** (`AirJedi/AirJedi/Services/AlertEngine.swift`): Evaluates configurable rules (proximity, watchlist, squawk, aircraft type) with 5-minute cooldown per aircraft to prevent notification spam.

**SettingsManager** (`AirJedi/AirJedi/App/SettingsManager.swift`): Singleton using `@AppStorage` for UserDefaults persistence. Stores source configs as JSON-encoded data.

### Project Structure

```
AirJedi/
├── project.yml          # XcodeGen configuration (macOS 14.0+, Swift 5.9)
└── AirJedi/
    ├── AirJediApp.swift # Entry point with MenuBarExtra
    ├── App/             # AppState, SettingsManager
    ├── Models/          # Aircraft, Coordinate, SourceConfig, AlertModels
    ├── Providers/       # ADSBProvider protocol + implementations
    ├── Services/        # AircraftService, AlertEngine, NotificationManager
    └── Views/           # MenuBarIcon, AircraftListView, Settings tabs
```

### Important Patterns

- All services use `@MainActor` for thread safety
- TCP providers use `NWConnection` via shared `TCPConnection` helper with exponential backoff retry
- SBS parser must use `components(separatedBy:)` for reliable CRLF detection
- Settings changes trigger provider restart via Combine with 500ms debouncing

## Configuration

Settings stored in `~/Library/Preferences/com.airjedi.notifier.plist`:
- `sourcesData`: JSON-encoded array of `SourceConfig`
- `showAircraftWithoutPosition`: Filter toggle for position-less aircraft
- `staleThresholdSeconds`: When to remove aircraft (60s default)
- `maxAircraftDisplay`: Display limit (25 default)
