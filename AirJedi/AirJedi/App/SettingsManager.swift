import SwiftUI
import Combine

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // MARK: - Sources

    @AppStorage("sourcesData") private var sourcesData: Data = Data()

    var sources: [SourceConfig] {
        get {
            guard !sourcesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([SourceConfig].self, from: sourcesData)) ?? []
        }
        set {
            sourcesData = (try? JSONEncoder().encode(newValue)) ?? Data()
            objectWillChange.send()
        }
    }

    func addSource(_ source: SourceConfig) {
        var current = sources
        current.append(source)
        sources = current
    }

    func updateSource(_ source: SourceConfig) {
        var current = sources
        if let index = current.firstIndex(where: { $0.id == source.id }) {
            current[index] = source
            sources = current
        }
    }

    func deleteSource(id: UUID) {
        var current = sources
        current.removeAll { $0.id == id }
        sources = current
    }

    func moveSource(from: IndexSet, to: Int) {
        var current = sources
        current.move(fromOffsets: from, toOffset: to)
        // Update priorities based on new order
        for (index, var source) in current.enumerated() {
            source.priority = index
            current[index] = source
        }
        sources = current
    }

    // MARK: - Location

    @AppStorage("refLatitude") var refLatitude: Double = 37.7749
    @AppStorage("refLongitude") var refLongitude: Double = -122.4194
    @AppStorage("locationName") var locationName: String = "San Francisco"

    var referenceLocation: Coordinate {
        Coordinate(latitude: refLatitude, longitude: refLongitude)
    }

    func setLocation(latitude: Double, longitude: Double, name: String = "") {
        refLatitude = latitude
        refLongitude = longitude
        locationName = name
        objectWillChange.send()
    }

    // MARK: - Display

    @AppStorage("refreshInterval") var refreshInterval: Double = 5.0
    @AppStorage("maxAircraftDisplay") var maxAircraftDisplay: Int = 25
    @AppStorage("staleThresholdSeconds") var staleThresholdSeconds: Int = 60
    @AppStorage("showAircraftWithoutPosition") var showAircraftWithoutPosition: Bool = false

    // MARK: - Init

    private init() {}
}
