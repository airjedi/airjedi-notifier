import AppKit
import SwiftUI

/// Manages map windows for aircraft, preventing duplicates and handling window lifecycle
@MainActor
final class MapWindowController {
    /// Singleton instance
    static let shared = MapWindowController()

    /// Track open windows by aircraft ICAO hex
    private var openWindows: [String: NSWindow] = [:]
    /// Keep delegates alive (window.delegate is weak)
    private var windowDelegates: [String: WindowDelegate] = [:]

    private init() {}

    /// Opens a map window for the given aircraft, or brings existing window to front
    func openMapWindow(for aircraft: Aircraft, referenceLocation: Coordinate?) {
        let key = aircraft.icaoHex

        // Check if window already exists for this aircraft
        if let existingWindow = openWindows[key], existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create the SwiftUI view
        let mapView = AircraftMapWindowView(
            aircraft: aircraft,
            referenceLocation: referenceLocation
        )

        // Create the hosting controller
        let hostingController = NSHostingController(rootView: mapView)

        // Create the window
        let window = NSWindow(contentViewController: hostingController)
        window.title = aircraft.callsign ?? aircraft.icaoHex
        window.setContentSize(NSSize(width: 600, height: 500))
        window.minSize = NSSize(width: 400, height: 300)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.center()

        // Track window closure to clean up our dictionary
        let delegate = WindowDelegate(controller: self, key: key)
        windowDelegates[key] = delegate
        window.delegate = delegate

        // Store and show
        openWindows[key] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called when a window closes to clean up tracking
    fileprivate func windowDidClose(key: String) {
        openWindows.removeValue(forKey: key)
        windowDelegates.removeValue(forKey: key)
    }
}

/// Delegate to handle window close events
private class WindowDelegate: NSObject, NSWindowDelegate {
    private weak var controller: MapWindowController?
    private let key: String

    init(controller: MapWindowController, key: String) {
        self.controller = controller
        self.key = key
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            controller?.windowDidClose(key: key)
        }
    }
}
