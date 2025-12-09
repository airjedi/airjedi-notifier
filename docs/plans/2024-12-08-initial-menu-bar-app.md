# AirJedi Initial Menu Bar App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a minimal macOS menu bar app with an airplane icon that displays a placeholder aircraft list.

**Architecture:** SwiftUI app using MenuBarExtra for menu bar presence. No dock icon. AppState holds placeholder data. Clean separation ready for real providers later.

**Tech Stack:** Swift 5.9+, SwiftUI, MenuBarExtra, Xcode 15+

---

## Task 1: Create Xcode Project

**Files:**
- Create: `AirJedi/AirJedi.xcodeproj`
- Create: `AirJedi/AirJedi/AirJediApp.swift`

**Step 1: Create the Xcode project using command line**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier
mkdir -p AirJedi/AirJedi
```

**Step 2: Create the app entry point**

Create file `AirJedi/AirJedi/AirJediApp.swift`:

```swift
import SwiftUI

@main
struct AirJediApp: App {
    var body: some Scene {
        MenuBarExtra("AirJedi", systemImage: "airplane") {
            Text("AirJedi")
                .padding()
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
```

**Step 3: Create the Xcode project file**

Create file `AirJedi/AirJedi.xcodeproj/project.pbxproj` with proper structure for a menu bar app (LSUIElement = YES to hide dock icon).

**Step 4: Build and run to verify menu bar icon appears**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodebuild -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds, app shows airplane icon in menu bar.

**Step 5: Commit**

```bash
git add AirJedi/
git commit -m "Create initial Xcode project with menu bar app"
```

---

## Task 2: Add Core Models

**Files:**
- Create: `AirJedi/AirJedi/Models/Aircraft.swift`
- Create: `AirJedi/AirJedi/Models/Coordinate.swift`

**Step 1: Create Coordinate model**

Create file `AirJedi/AirJedi/Models/Coordinate.swift`:

```swift
import Foundation

struct Coordinate: Equatable, Codable {
    let latitude: Double
    let longitude: Double

    /// Calculate distance to another coordinate in nautical miles
    func distance(to other: Coordinate) -> Double {
        let earthRadiusNm = 3440.065

        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1) * cos(lat2) *
                sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusNm * c
    }
}
```

**Step 2: Create Aircraft model**

Create file `AirJedi/AirJedi/Models/Aircraft.swift`:

```swift
import Foundation

struct Aircraft: Identifiable, Equatable {
    let icaoHex: String
    var callsign: String?
    var position: Coordinate?
    var altitudeFeet: Int?
    var headingDegrees: Double?
    var speedKnots: Double?
    var verticalRateFpm: Double?
    var squawk: String?
    var lastSeen: Date

    // Enriched data
    var registration: String?
    var aircraftTypeCode: String?
    var operatorName: String?

    var id: String { icaoHex }

    /// Distance from a reference point in nautical miles
    func distance(from reference: Coordinate) -> Double? {
        guard let position = position else { return nil }
        return reference.distance(to: position)
    }
}
```

**Step 3: Build to verify models compile**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodebuild -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 4: Commit**

```bash
git add AirJedi/AirJedi/Models/
git commit -m "Add Aircraft and Coordinate models"
```

---

## Task 3: Create AppState with Placeholder Data

**Files:**
- Create: `AirJedi/AirJedi/App/AppState.swift`

**Step 1: Create AppState**

Create file `AirJedi/AirJedi/App/AppState.swift`:

```swift
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var aircraft: [Aircraft] = []
    @Published var referenceLocation: Coordinate?

    var nearbyCount: Int {
        aircraft.count
    }

    init() {
        // Load placeholder data for development
        loadPlaceholderData()
    }

    private func loadPlaceholderData() {
        // Reference location: San Francisco
        referenceLocation = Coordinate(latitude: 37.7749, longitude: -122.4194)

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

**Step 2: Build to verify AppState compiles**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodebuild -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/App/
git commit -m "Add AppState with placeholder aircraft data"
```

---

## Task 4: Create Menu Bar Icon View

**Files:**
- Create: `AirJedi/AirJedi/Views/MenuBarIcon.swift`

**Step 1: Create MenuBarIcon view**

Create file `AirJedi/AirJedi/Views/MenuBarIcon.swift`:

```swift
import SwiftUI

struct MenuBarIcon: View {
    let aircraftCount: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "airplane")
                .font(.system(size: 14))

            if aircraftCount > 0 {
                Text("\(aircraftCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Circle().fill(Color.blue))
                    .offset(x: 6, y: -4)
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        MenuBarIcon(aircraftCount: 0)
        MenuBarIcon(aircraftCount: 3)
        MenuBarIcon(aircraftCount: 12)
    }
    .padding()
}
```

**Step 2: Build to verify view compiles**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodebuild -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Views/
git commit -m "Add MenuBarIcon view with aircraft count badge"
```

---

## Task 5: Create Aircraft Row View

**Files:**
- Create: `AirJedi/AirJedi/Views/AircraftRowView.swift`

**Step 1: Create AircraftRowView**

Create file `AirJedi/AirJedi/Views/AircraftRowView.swift`:

```swift
import SwiftUI

struct AircraftRowView: View {
    let aircraft: Aircraft
    let referenceLocation: Coordinate?

    private var distanceText: String {
        guard let ref = referenceLocation,
              let dist = aircraft.distance(from: ref) else {
            return "--"
        }
        return String(format: "%.1fnm", dist)
    }

    private var altitudeText: String {
        guard let alt = aircraft.altitudeFeet else { return "--" }
        return "\(alt.formatted())ft"
    }

    private var headingText: String {
        guard let hdg = aircraft.headingDegrees else { return "" }
        return String(format: "↗%.0f°", hdg)
    }

    private var speedText: String {
        guard let spd = aircraft.speedKnots else { return "" }
        return "\(Int(spd))kt"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "airplane")
                    .font(.system(size: 10))
                Text(aircraft.callsign ?? aircraft.icaoHex)
                    .font(.system(size: 12, weight: .semibold))

                if let typeCode = aircraft.aircraftTypeCode {
                    Text(typeCode)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(altitudeText)
                    .font(.system(size: 11, weight: .medium))

                Text(distanceText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)
            }

            HStack {
                if let opName = aircraft.operatorName {
                    Text(opName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(headingText) \(speedText)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

#Preview {
    let aircraft = Aircraft(
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
    )

    AircraftRowView(
        aircraft: aircraft,
        referenceLocation: Coordinate(latitude: 37.7749, longitude: -122.4194)
    )
    .frame(width: 280)
}
```

**Step 2: Build to verify view compiles**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodebuild -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Views/AircraftRowView.swift
git commit -m "Add AircraftRowView with distance and details"
```

---

## Task 6: Create Aircraft List View

**Files:**
- Create: `AirJedi/AirJedi/Views/AircraftListView.swift`

**Step 1: Create AircraftListView**

Create file `AirJedi/AirJedi/Views/AircraftListView.swift`:

```swift
import SwiftUI

struct AircraftListView: View {
    @ObservedObject var appState: AppState

    private var sortedAircraft: [Aircraft] {
        guard let ref = appState.referenceLocation else {
            return appState.aircraft
        }
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

**Step 2: Build to verify view compiles**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodebuild -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Views/AircraftListView.swift
git commit -m "Add AircraftListView with sorted aircraft display"
```

---

## Task 7: Wire Up App Entry Point

**Files:**
- Modify: `AirJedi/AirJedi/AirJediApp.swift`

**Step 1: Update AirJediApp to use AppState and views**

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
            MenuBarIcon(aircraftCount: appState.nearbyCount)
        }
        .menuBarExtraStyle(.window)
    }
}
```

**Step 2: Build and run to verify full integration**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodebuild -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds. Running app shows airplane icon with badge "3", clicking shows placeholder aircraft.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/AirJediApp.swift
git commit -m "Wire up AppState and views in main app entry point"
```

---

## Task 8: Configure as Menu Bar Only App

**Files:**
- Create: `AirJedi/AirJedi/Info.plist`

**Step 1: Create Info.plist with LSUIElement**

Create file `AirJedi/AirJedi/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>AirJedi</string>
    <key>CFBundleDisplayName</key>
    <string>AirJedi</string>
    <key>CFBundleIdentifier</key>
    <string>com.airjedi.notifier</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
```

**Step 2: Build and run to verify no dock icon**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodebuild -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds. App runs without dock icon, only menu bar presence.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Info.plist
git commit -m "Configure app as menu bar only (no dock icon)"
```

---

## Summary

After completing all tasks, you will have:
- A macOS menu bar app with airplane icon and aircraft count badge
- Core models (Aircraft, Coordinate) ready for real data
- AppState architecture ready for providers and services
- Placeholder data showing 3 aircraft for UI development
- No dock icon (menu bar only presence)

The foundation is ready for adding real ADS-B providers in subsequent iterations.
