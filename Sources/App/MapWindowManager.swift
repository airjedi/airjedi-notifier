import AppKit
import SwiftUI

/// Manages opening aircraft map windows
@MainActor
final class MapWindowManager {
    static let shared = MapWindowManager()

    private var openWindows: [String: NSWindow] = [:]

    /// The aircraft service used for live aircraft data (uses Combine @Published)
    private var aircraftService: AircraftService?

    private init() {}

    /// Configure the manager with the aircraft service for live updates
    func configure(aircraftService: AircraftService) {
        self.aircraftService = aircraftService
    }

    func openMapWindow(for aircraft: Aircraft, referenceLocation: Coordinate?) {
        // If window already exists for this aircraft, bring it to front
        if let existingWindow = openWindows[aircraft.icaoHex] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let aircraftService = aircraftService else {
            print("MapWindowManager: aircraftService not configured, cannot open map window")
            return
        }

        // Create the SwiftUI view with Combine subscription for live updates
        let mapView = AircraftMapWindow(
            icaoHex: aircraft.icaoHex,
            aircraftService: aircraftService,
            referenceLocation: referenceLocation,
            initialAircraft: aircraft
        )

        // Create the hosting controller
        let hostingController = NSHostingController(rootView: mapView)

        // Create the window
        let window = NSWindow(contentViewController: hostingController)
        window.title = "\(aircraft.callsign ?? aircraft.icaoHex) - Map"
        window.setContentSize(NSSize(width: 600, height: 500))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false

        // Track the window
        openWindows[aircraft.icaoHex] = window

        // Clean up when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            if let closedWindow = notification.object as? NSWindow {
                self?.openWindows.removeValue(forKey: aircraft.icaoHex)
            }
        }

        // Show the window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
