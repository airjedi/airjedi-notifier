import SwiftUI
import MapKit

/// A static mini-map showing an aircraft's position with heading indicator
struct AircraftMiniMapView: View {
    let position: Coordinate
    let headingDegrees: Double?

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: position.clLocationCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            Annotation("", coordinate: position.clLocationCoordinate) {
                Image(systemName: "airplane")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees((headingDegrees ?? 0) - 90))
                    .shadow(color: .white, radius: 1)
            }
        }
        .frame(width: 150, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    AircraftMiniMapView(
        position: Coordinate(latitude: 37.8, longitude: -122.4),
        headingDegrees: 280
    )
    .padding()
}
