import SwiftUI

/// Detailed view of aircraft information, used in hover popovers and as a template for notifications
struct AircraftDetailView: View {
    let aircraft: Aircraft
    let referenceLocation: Coordinate?

    private var distanceText: String? {
        guard let ref = referenceLocation,
              let dist = aircraft.distance(from: ref) else {
            return nil
        }
        return String(format: "%.1f nm", dist)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            detailContent(now: context.date)
        }
    }

    private func detailContent(now: Date) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Mini-map (only if position exists) - click to open full map
            if aircraft.position != nil {
                AircraftMiniMapView(
                    aircraft: aircraft,
                    referenceLocation: referenceLocation
                )
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    MapWindowManager.shared.openMapWindow(for: aircraft, referenceLocation: referenceLocation)
                }
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .help("Click to open larger map")
            }

            // Details panel
            VStack(alignment: .leading, spacing: 8) {
                // Header: Callsign/ICAO and operator
                HStack {
                    Image(systemName: "airplane")
                        .font(.system(size: 14))
                    Text(aircraft.callsign ?? aircraft.icaoHex)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                }

                if let opName = aircraft.operatorName {
                    Text(opName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Divider()

                // Details grid
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    if let typeCode = aircraft.aircraftTypeCode {
                        GridRow {
                            Text("Type:")
                                .foregroundColor(.secondary)
                            Text(typeCode)
                        }
                    }

                    if let reg = aircraft.registration {
                        GridRow {
                            Text("Registration:")
                                .foregroundColor(.secondary)
                            Text(reg)
                        }
                    }

                    GridRow {
                        Text("ICAO:")
                            .foregroundColor(.secondary)
                        Text(aircraft.icaoHex)
                    }

                    if let alt = aircraft.altitudeFeet {
                        GridRow {
                            Text("Altitude:")
                                .foregroundColor(.secondary)
                            Text("\(alt.formatted()) ft")
                        }
                    }

                    if let speed = aircraft.speedKnots {
                        GridRow {
                            Text("Speed:")
                                .foregroundColor(.secondary)
                            Text("\(Int(speed)) kt")
                        }
                    }

                    if let heading = aircraft.headingDegrees {
                        GridRow {
                            Text("Heading:")
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f°", heading))
                        }
                    }

                    if let vRate = aircraft.verticalRateFpm, vRate != 0 {
                        GridRow {
                            Text("Vertical:")
                                .foregroundColor(.secondary)
                            Text("\(vRate > 0 ? "+" : "")\(Int(vRate)) fpm")
                        }
                    }

                    if let squawk = aircraft.squawk {
                        GridRow {
                            Text("Squawk:")
                                .foregroundColor(.secondary)
                            Text(squawk)
                                .foregroundColor(isEmergencySquawk(squawk) ? .red : .primary)
                        }
                    }

                    if let distance = distanceText {
                        GridRow {
                            Text("Distance:")
                                .foregroundColor(.secondary)
                            Text(distance)
                                .foregroundColor(.blue)
                        }
                    }

                    if let position = aircraft.position {
                        GridRow {
                            Text("Position:")
                                .foregroundColor(.secondary)
                            Text(String(format: "%.4f, %.4f", position.latitude, position.longitude))
                                .font(.system(size: 10, design: .monospaced))
                        }
                    }

                    GridRow {
                        Text("Last Seen:")
                            .foregroundColor(.secondary)
                        Text(aircraft.lastSeen.elapsedTextWithAgo(now: now))
                            .foregroundColor(aircraft.lastSeen.freshnessColor(now: now))
                    }
                }
                .font(.system(size: 11))
            }
        }
        .padding(12)
        .frame(minWidth: 200)
    }

    private func isEmergencySquawk(_ code: String) -> Bool {
        ["7500", "7600", "7700"].contains(code)
    }
}

// MARK: - Text Summary for Notifications

extension Aircraft {
    /// Generates a subtitle line for notifications (type, registration, operator)
    var notificationSubtitle: String {
        var parts: [String] = []
        if let typeCode = aircraftTypeCode {
            parts.append(typeCode)
        }
        if let reg = registration {
            parts.append("(\(reg))")
        }
        if let opName = operatorName {
            parts.append("· \(opName)")
        }
        return parts.isEmpty ? icaoHex : parts.joined(separator: " ")
    }

    /// Generates a multi-line text summary suitable for notifications
    func detailSummary(referenceLocation: Coordinate?) -> String {
        var lines: [String] = []

        // Type and registration line
        var identLine: [String] = []
        if let typeCode = aircraftTypeCode {
            identLine.append(typeCode)
        }
        if let reg = registration {
            identLine.append("(\(reg))")
        }
        if !identLine.isEmpty {
            lines.append(identLine.joined(separator: " "))
        }

        // Flight data line
        var flightLine: [String] = []
        if let alt = altitudeFeet {
            flightLine.append("\(alt.formatted())ft")
        }
        if let speed = speedKnots {
            flightLine.append("\(Int(speed))kt")
        }
        if let heading = headingDegrees {
            flightLine.append(String(format: "%.0f°", heading))
        }
        if !flightLine.isEmpty {
            lines.append(flightLine.joined(separator: " · "))
        }

        // Distance line
        if let ref = referenceLocation, let dist = distance(from: ref) {
            lines.append(String(format: "%.1f nm away", dist))
        }

        // Squawk (if notable)
        if let squawk = squawk, squawk != "1200" {
            lines.append("Squawk: \(squawk)")
        }

        return lines.joined(separator: "\n")
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

    AircraftDetailView(
        aircraft: aircraft,
        referenceLocation: Coordinate(latitude: 37.7749, longitude: -122.4194)
    )
}
