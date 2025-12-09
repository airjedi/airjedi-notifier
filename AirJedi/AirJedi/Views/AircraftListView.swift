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
