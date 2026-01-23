# Alert Highlight Color Feature Design

## Overview

Add configurable highlight colors to alert rules. When an alert condition is active for an aircraft, the callsign/ICAO text in the aircraft list displays in the configured color. When the condition no longer applies, the text returns to the default color.

## Data Model

### AlertColor (new struct)

```swift
struct AlertColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var color: Color { ... }
    init(color: Color) { ... }
}
```

Stores RGBA components for Codable persistence since SwiftUI Color is not directly Codable.

### AlertRuleConfig (modified)

Add optional property:
```swift
var highlightColor: AlertColor?  // nil = no highlighting
```

Custom decoder handles existing saved rules without this field.

## Active Alert Tracking

### AlertEngine (modified)

New published property:
```swift
@Published private(set) var activeAlertColors: [String: Color] = [:]  // icaoHex -> color
```

New method `updateActiveAlerts(aircraft:)`:
1. Iterates all enabled rules for each aircraft
2. Checks if conditions are currently met (not first-detection logic)
3. Builds icaoHex -> Color map
4. Last matching rule wins (most recent takes priority)

Called on every aircraft update cycle, separate from notification-triggering `evaluate()`.

## UI Changes

### AlertRuleDetailView

Add to General section:
- Toggle: "Enable Highlighting"
- ColorPicker: "Highlight Color" (appears when toggle is on)

### AircraftRowView

New parameter:
```swift
let highlightColor: Color?
```

Apply to callsign text:
```swift
Text(aircraft.callsign ?? aircraft.icaoHex)
    .foregroundColor(highlightColor ?? .primary)
```

### AircraftListView

Pass highlight color from AlertEngine:
```swift
AircraftRowView(
    aircraft: aircraft,
    referenceLocation: appState.referenceLocation,
    highlightColor: appState.alertEngine.activeAlertColors[aircraft.icaoHex]
)
```

## Data Flow

```
AircraftService updates
    → AppState receives
    → calls alertEngine.updateActiveAlerts(aircraft:)
    → activeAlertColors updates
    → SwiftUI observes @Published change
    → AircraftRowView re-renders with new color
```

## Condition Matching

Each rule type checks current state (simpler than notification first-detection logic):

| Rule Type | Condition |
|-----------|-----------|
| Proximity | Aircraft within distance and altitude bounds |
| Watchlist | Callsign, registration, or ICAO matches list |
| Squawk | Squawk code in configured list |
| AircraftType | Type code matches list |

## Edge Cases

- Aircraft removed from list: naturally disappears from activeAlertColors on next cycle
- Multiple rules match: last matching rule's color wins
- Rule disabled: stops contributing to activeAlertColors
- No highlight color configured: rule doesn't affect callsign color
