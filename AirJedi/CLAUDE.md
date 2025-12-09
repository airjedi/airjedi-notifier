# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

This project uses xcodegen to generate the Xcode project from `project.yml`:

```bash
# Generate Xcode project (required after adding/removing files or changing project.yml)
xcodegen generate

# Build
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build

# Run the app
open /Users/ccustine/Library/Developer/Xcode/DerivedData/AirJedi-*/Build/Products/Debug/AirJedi.app
```

The `.xcodeproj` is generated and not committed - always run `xcodegen generate` after pulling or modifying file structure.

## Architecture Overview

AirJedi is a macOS menu bar app (LSUIElement) that displays nearby aircraft from ADS-B receivers.

### Data Flow

```
ADS-B Receivers → Providers → AircraftService → AppState → Views
                                    ↓
                              AlertEngine → NotificationManager
```

### Key Components

**AppState** (`App/AppState.swift`): Central coordinator that owns all services and forwards Combine `objectWillChange` events to trigger SwiftUI updates.

**Providers** (`Providers/`): Protocol-based ADS-B data sources implementing `ADSBProvider`:
- `Dump1090Provider` - HTTP JSON polling (port 8080)
- `SBSProvider` - TCP text stream (port 30003, uses CRLF line endings)
- `BeastProvider` - TCP binary AVR frames (port 30005)

All providers emit `AircraftUpdate` events via Combine publishers. `ProviderManager` coordinates multiple sources and subscribes `AircraftService` to their updates.

**AircraftService** (`Services/AircraftService.swift`): Maintains aircraft cache keyed by ICAO hex, handles deduplication, staleness removal, and filtering by position/distance.

**AlertEngine** (`Services/AlertEngine.swift`): Evaluates configurable rules (proximity, watchlist, squawk, aircraft type) against aircraft updates. Uses cooldown to prevent notification spam.

**SettingsManager** (`App/SettingsManager.swift`): Singleton using `@AppStorage` for UserDefaults persistence. Stores source configs as JSON-encoded data.

### SwiftUI Structure

- `MenuBarExtra` with `.window` style for the aircraft list dropdown
- `Settings` scene with tabbed interface (Sources, Location, Display, Alerts)
- All views observe `AppState` which aggregates changes from services

### Important Patterns

- All services use `@MainActor` for thread safety
- TCP providers use `NWConnection` (Network.framework) via `TCPConnection` helper
- SBS parser must use `components(separatedBy:)` instead of `firstIndex(of:)` for reliable newline detection
- Settings use Combine's `objectWillChange` with debouncing to sync provider state

## Configuration

Settings are stored in `~/Library/Preferences/com.airjedi.notifier.plist`. Key values:
- `sourcesData`: JSON-encoded array of `SourceConfig`
- `showAircraftWithoutPosition`: Whether to display aircraft lacking position data
