import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocating = false
    @Published var error: String?

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestCurrentLocation() async throws -> CLLocation {
        isLocating = true
        error = nil

        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation

            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            } else if locationManager.authorizationStatus == .authorizedAlways {
                locationManager.requestLocation()
            } else {
                continuation.resume(throwing: LocationError.notAuthorized)
                self.locationContinuation = nil
                self.isLocating = false
            }
        }
    }

    enum LocationError: LocalizedError {
        case notAuthorized
        case locationUnavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Location access not authorized"
            case .locationUnavailable: return "Unable to determine location"
            }
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isLocating = false
        if let location = locations.last {
            lastLocation = location
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        self.error = error.localizedDescription
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways && locationContinuation != nil {
            manager.requestLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            locationContinuation?.resume(throwing: LocationError.notAuthorized)
            locationContinuation = nil
            isLocating = false
        }
    }
}
