import SwiftUI

struct AircraftRowView: View {
    let aircraft: Aircraft
    let referenceLocation: Coordinate?
    let highlightColor: Color?

    @State private var isHovering = false
    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?

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
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            rowContent(now: context.date)
        }
    }

    private func rowContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "airplane")
                    .font(.system(size: 10))
                Text(aircraft.callsign ?? aircraft.icaoHex)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(highlightColor ?? .primary)

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

                Text(aircraft.lastSeen.elapsedCompactText(now: now))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(aircraft.lastSeen.freshnessColor(now: now))

                Text("\(headingText) \(speedText)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            hoverTask?.cancel()

            if hovering {
                // Show popover immediately on hover
                showPopover = true
            } else {
                // Delay hiding popover by 1.5 seconds
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if !Task.isCancelled {
                        showPopover = false
                    }
                }
            }
        }
        .onTapGesture {
            if aircraft.position != nil {
                showPopover = false
                MapWindowManager.shared.openMapWindow(
                    for: aircraft,
                    referenceLocation: referenceLocation
                )
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            AircraftDetailView(aircraft: aircraft, referenceLocation: referenceLocation)
                .onHover { hoveringPopover in
                    if hoveringPopover {
                        // Cancel close if hovering over popover
                        hoverTask?.cancel()
                    } else {
                        // Start close timer when leaving popover
                        hoverTask = Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            if !Task.isCancelled {
                                showPopover = false
                            }
                        }
                    }
                }
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

    AircraftRowView(
        aircraft: aircraft,
        referenceLocation: Coordinate(latitude: 37.7749, longitude: -122.4194),
        highlightColor: nil
    )
    .frame(width: 280)
}
