import SwiftUI
import MapKit
import Combine

/// A larger, interactive map window for viewing an aircraft's position
struct AircraftMapWindow: View {
    let icaoHex: String
    let aircraftService: AircraftService
    let referenceLocation: Coordinate?

    /// Whether to follow the aircraft as it moves
    @State private var followAircraft: Bool = true
    @State private var mapCameraPosition: MapCameraPosition

    /// Current aircraft data, updated via Combine subscription
    @State private var aircraft: Aircraft?

    init(icaoHex: String, aircraftService: AircraftService, referenceLocation: Coordinate?, initialAircraft: Aircraft) {
        self.icaoHex = icaoHex
        self.aircraftService = aircraftService
        self.referenceLocation = referenceLocation
        self._aircraft = State(initialValue: initialAircraft)

        // Initialize camera centered on aircraft or reference location
        let center = initialAircraft.position?.clLocationCoordinate
            ?? referenceLocation?.clLocationCoordinate
            ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        _mapCameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with aircraft info
            header

            Divider()

            // Interactive map
            Map(position: $mapCameraPosition) {
                // Aircraft marker (using live data)
                if let ac = aircraft, let position = ac.position {
                    Annotation(ac.callsign ?? ac.icaoHex, coordinate: position.clLocationCoordinate) {
                        Image(systemName: "airplane")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees((ac.headingDegrees ?? 0) - 90))
                    }
                }

                // Reference location marker
                if let ref = referenceLocation {
                    Annotation("Home", coordinate: ref.clLocationCoordinate) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .environment(\.colorScheme, .dark)
            .mapControls {
                MapZoomStepper()
                MapCompass()
                MapScaleView()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .overlay(alignment: .topTrailing) {
            // Aircraft gone indicator
            if aircraft == nil {
                Label("Aircraft no longer tracked", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.orange.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
        }
        .onReceive(aircraftService.$aircraft) { allAircraft in
            // Update our tracked aircraft from the live data
            let updated = allAircraft.first { $0.icaoHex == icaoHex }

            // Check if position changed for camera follow
            if followAircraft,
               let newPosition = updated?.position,
               newPosition != aircraft?.position {
                withAnimation(.easeInOut(duration: 0.3)) {
                    mapCameraPosition = .region(MKCoordinateRegion(
                        center: newPosition.clLocationCoordinate,
                        span: currentSpan
                    ))
                }
            }

            aircraft = updated
        }
    }

    /// Extract current span from camera position for smooth updates
    private var currentSpan: MKCoordinateSpan {
        // MapCameraPosition.region stores the region but we can't pattern match it directly
        // Use a default span instead of trying to extract from the current position
        MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    }

    private var header: some View {
        HStack {
            Image(systemName: "airplane")
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(aircraft?.callsign ?? icaoHex)
                    .font(.system(size: 14, weight: .bold))

                if let opName = aircraft?.operatorName {
                    Text(opName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Follow toggle button
            Button {
                followAircraft.toggle()
            } label: {
                Image(systemName: followAircraft ? "location.fill" : "location")
                    .font(.system(size: 12))
                    .foregroundColor(followAircraft ? .blue : .secondary)
            }
            .buttonStyle(.borderless)
            .help(followAircraft ? "Following aircraft (click to stop)" : "Click to follow aircraft")

            // Flight info badges
            HStack(spacing: 12) {
                if let alt = aircraft?.altitudeFeet {
                    Badge(icon: "arrow.up", text: "\(alt.formatted()) ft")
                }

                if let speed = aircraft?.speedKnots {
                    Badge(icon: "speedometer", text: "\(Int(speed)) kt")
                }

                if let heading = aircraft?.headingDegrees {
                    Badge(icon: "safari", text: String(format: "%.0f°", heading))
                }

                if let ref = referenceLocation, let ac = aircraft, let dist = ac.distance(from: ref) {
                    Badge(icon: "location", text: String(format: "%.1f nm", dist))
                }

                if let ac = aircraft {
                    LastSeenBadge(lastSeen: ac.lastSeen)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct Badge: View {
    let icon: String
    let text: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
    }
}

/// Badge that displays time since last seen with auto-updating
private struct LastSeenBadge: View {
    let lastSeen: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Badge(
                icon: "clock",
                text: lastSeen.elapsedCompactText(now: context.date),
                color: lastSeen.freshnessColor(now: context.date)
            )
        }
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
        verticalRateFpm: -500,
        squawk: "1200",
        lastSeen: Date(),
        registration: "N12345",
        aircraftTypeCode: "B738",
        operatorName: "United Airlines"
    )

    AircraftMapWindow(
        icaoHex: aircraft.icaoHex,
        aircraftService: AircraftService(),
        referenceLocation: Coordinate(latitude: 37.7749, longitude: -122.4194),
        initialAircraft: aircraft
    )
}
