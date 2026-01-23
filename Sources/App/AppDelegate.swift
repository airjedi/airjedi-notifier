import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var appState: AppState!
    private var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the app state
        appState = AppState()

        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "airplane", accessibilityDescription: "AirJedi")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create the popover with SwiftUI content
        popover = NSPopover()
        popover.contentSize = NSSize(width: 350, height: 400)
        popover.behavior = .semitransient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: AircraftListView(appState: appState))

        // Start timer to poll for updates (reliable approach)
        startUpdateTimer()
    }

    private func startUpdateTimer() {
        // Poll every second to update the status bar
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusButton()
            }
        }
        // Also do an immediate update
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let count = appState.nearbyCount
        let status = appState.connectionStatus
        let hasAlert = appState.hasRecentAlert

        // Update image based on status
        let imageName: String
        var imageColor: NSColor? = nil

        if hasAlert {
            imageName = "airplane"
            imageColor = .orange
        } else {
            switch status {
            case .error:
                imageName = "airplane.circle.fill"
                imageColor = .red
            case .disconnected:
                imageName = "airplane"
                imageColor = .secondaryLabelColor
            default:
                imageName = "airplane"
            }
        }

        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "AirJedi") {
            if let color = imageColor {
                button.image = image.withSymbolConfiguration(.init(paletteColors: [color]))
            } else {
                button.image = image
            }
        }

        // Update title with count if connected and has aircraft
        if count > 0 && status.isConnected {
            button.title = " \(count)"
        } else {
            button.title = ""
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
