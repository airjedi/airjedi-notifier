# AirJedi

A lightweight macOS menu bar app for tracking nearby aircraft using ADS-B receivers.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-Apache%202.0-blue)

## Features

- **Menu Bar Integration** — Lives in your menu bar, always accessible without cluttering your Dock
- **Multiple ADS-B Sources** — Connect to dump1090, SBS (BaseStation), or Beast protocol receivers
- **Real-time Updates** — See aircraft appear and update as they fly through your area, with color-coded freshness indicators
- **Configurable Alerts** — Get notified for proximity, specific squawk codes, watchlist aircraft, or aircraft types
- **Highlight Colors** — Assign custom colors to alert rules for visual identification
- **Mini-map View** — Quick visual overview of aircraft positions relative to your location
- **Distance Filtering** — Focus on aircraft within a specific range

## Requirements

- macOS 14.0 (Sonoma) or later
- An ADS-B receiver accessible on your network (e.g., RTL-SDR with dump1090, FlightAware PiAware, or similar)

## Installation

### From Release

Download the latest release from the [Releases](https://github.com/airjedi/airjedi-notifier/releases) page and drag `AirJedi.app` to your Applications folder.

### From Source

```bash
# Install xcodegen if you haven't already
brew install xcodegen

# Clone the repository
git clone https://github.com/airjedi/airjedi-notifier.git
cd airjedi-notifier

# Build and install
make install
```

## Usage

1. Launch AirJedi from your Applications folder
2. Click the airplane icon in the menu bar
3. Open **Settings** to configure your ADS-B sources
4. Add a source with your receiver's IP address and select the protocol

### Supported Protocols

| Protocol | Default Port | Description |
|----------|-------------|-------------|
| **Dump1090** | 8080 | HTTP JSON polling — works with dump1090-fa, readsb, tar1090 |
| **SBS/BaseStation** | 30003 | TCP text stream — widely supported format |
| **Beast** | 30005 | TCP binary AVR frames — low-latency, efficient |

## Configuration

AirJedi stores settings in `~/Library/Preferences/com.airjedi.notifier.plist`. You can configure:

- **Sources** — Multiple ADS-B receiver connections
- **Display Settings** — Maximum aircraft to show, stale threshold
- **Location** — Your position for distance calculations (or use automatic location)
- **Alerts** — Rules for proximity, squawk codes, ICAO watchlist, and aircraft types

### Alert Rules

Create custom alert rules to be notified when specific conditions are met:

- **Proximity** — Aircraft within a specified distance
- **Squawk Code** — Emergency (7500, 7600, 7700) or custom codes
- **Watchlist** — Specific ICAO hex codes you want to track
- **Aircraft Type** — Filter by aircraft type designator

Each rule can have a custom highlight color for easy visual identification in the aircraft list.

## Building

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

```bash
make build      # Generate project and build (Debug)
make run        # Build and launch the app
make release    # Build release configuration
make clean      # Remove build artifacts
make install    # Build release and install to /Applications
make generate   # Regenerate Xcode project only
```

## Project Structure

```
airjedi-notifier/
├── Sources/
│   ├── App/           # App entry point, state management, settings
│   ├── Models/        # Data models (Aircraft, Coordinate, etc.)
│   ├── Providers/     # ADS-B protocol implementations
│   ├── Services/      # Business logic (alerts, notifications)
│   ├── Utilities/     # Shared helpers (time formatting, etc.)
│   └── Views/         # SwiftUI views
├── Resources/
│   └── Info.plist
├── project.yml        # XcodeGen configuration
└── Makefile           # Build automation
```

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [dump1090](https://github.com/antirez/dump1090) and its many forks for ADS-B decoding
- The aviation enthusiast community for protocol documentation
