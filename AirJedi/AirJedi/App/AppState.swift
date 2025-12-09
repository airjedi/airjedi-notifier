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
