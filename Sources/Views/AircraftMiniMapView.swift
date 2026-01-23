import SwiftUI
import MapKit

/// A static mini-map showing an aircraft's position with heading indicator
/// Tap to open a full interactive map window
struct AircraftMiniMapView: View {
    let aircraft: Aircraft
    let referenceLocation: Coordinate?

    private var region: MKCoordinateRegion {
        guard let position = aircraft.position else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            )
        }
        return MKCoordinateRegion(
            center: position.clLocationCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    }

    var body: some View {
        ZStack {
            Map(initialPosition: .region(region), interactionModes: []) {
                if let position = aircraft.position {
                    Annotation("", coordinate: position.clLocationCoordinate) {
                        Image(systemName: "airplane")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees((aircraft.headingDegrees ?? 0) - 90))
                            .shadow(color: .white, radius: 1)
                    }
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)

            // Clear overlay to capture clicks
            Color.clear
                .frame(width: 150, height: 150)
                .contentShape(Rectangle())
                .onTapGesture {
                    MapWindowController.shared.openMapWindow(
                        for: aircraft,
                        referenceLocation: referenceLocation
                    )
                }
        }
        .help("Click to open full map")
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

    AircraftMiniMapView(
        aircraft: aircraft,
        referenceLocation: Coordinate(latitude: 37.7749, longitude: -122.4194)
    )
    .padding()
}
