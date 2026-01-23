import SwiftUI
import MapKit

/// Full interactive map view for displaying an aircraft's location in a separate window
struct AircraftMapWindowView: View {
    let aircraft: Aircraft
    let referenceLocation: Coordinate?

    private var region: MKCoordinateRegion {
        guard let position = aircraft.position else {
            // Fallback to a default region if no position
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
        return MKCoordinateRegion(
            center: position.clLocationCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        )
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            // Aircraft annotation
            if let position = aircraft.position {
                Annotation(
                    aircraft.callsign ?? aircraft.icaoHex,
                    coordinate: position.clLocationCoordinate
                ) {
                    Image(systemName: "airplane")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees((aircraft.headingDegrees ?? 0) - 90))
                        .shadow(color: .white, radius: 2)
                }
            }

            // Reference location marker (if available)
            if let ref = referenceLocation {
                Annotation("Home", coordinate: ref.clLocationCoordinate) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                        .shadow(color: .white, radius: 1)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapZoomStepper()
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
        verticalRateFpm: 0,
        squawk: "1200",
        lastSeen: Date(),
        registration: "N12345",
        aircraftTypeCode: "B738",
        operatorName: "United Airlines"
    )

    AircraftMapWindowView(
        aircraft: aircraft,
        referenceLocation: Coordinate(latitude: 37.7749, longitude: -122.4194)
    )
    .frame(width: 600, height: 500)
}
