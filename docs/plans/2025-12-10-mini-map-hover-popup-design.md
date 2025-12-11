# Mini-Map for Aircraft Hover Popup

**Date:** 2025-12-10
**Status:** Approved

## Summary

Add a static mini-map to the aircraft hover popup showing the aircraft position with a rotated airplane icon indicating heading direction.

## Design Decisions

| Aspect | Decision |
|--------|----------|
| Map content | Aircraft position with rotated airplane icon showing heading |
| Layout | Side-by-side: map on left (~150px), details on right |
| Behavior | Static snapshot, no pan/zoom interaction |
| Heading indicator | SF Symbol `airplane` rotated to match `headingDegrees` |
| Reference location | Not shown (aircraft only) |

## Implementation

### New File: `AirJedi/AirJedi/Views/AircraftMiniMapView.swift`

New SwiftUI view (~40-50 lines) that renders a static MapKit map:

- Uses SwiftUI `Map` with `interactionModes: []` (disables pan/zoom)
- `MKCoordinateRegion` centered on aircraft with 0.05° span (~3 miles)
- `Annotation` with rotated airplane SF Symbol
- Fixed 150x150 frame with rounded corners

### Modified: `AirJedi/AirJedi/Views/AircraftDetailView.swift`

Change body layout from `VStack` to `HStack`:

- Map on left (conditionally shown only if `aircraft.position != nil`)
- Existing details grid on right (unchanged internally)
- Graceful fallback to text-only when no position data

### Helper: `Coordinate` Extension

Add `clLocationCoordinate` computed property to convert `Coordinate` to `CLLocationCoordinate2D`.

## Edge Cases

| Case | Behavior |
|------|----------|
| No position data | Map hidden, text-only detail view |
| No heading data | Airplane icon shown pointing north (0°) |

## Files to Modify

1. `AirJedi/AirJedi/Views/AircraftMiniMapView.swift` (new)
2. `AirJedi/AirJedi/Views/AircraftDetailView.swift` (modify layout)
3. `AirJedi/AirJedi/Models/Coordinate.swift` (add extension)

## Difficulty

**Easy to Moderate** — SwiftUI MapKit is built-in, all required data already exists in the Aircraft model.
