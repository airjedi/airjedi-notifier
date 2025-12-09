import Foundation
import UserNotifications
import AppKit

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var isAuthorized = false
    @Published var alertsEnabled = true

    private init() {
        checkAuthorization()
    }

    // MARK: - Authorization

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await MainActor.run {
                isAuthorized = granted
            }
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Delivery

    func deliver(_ alert: Alert) async {
        guard alertsEnabled else { return }

        // Play sound
        playSound(alert.sound)

        // Send notification if authorized
        if isAuthorized {
            await sendNotification(alert)
        }
    }

    func deliverMultiple(_ alerts: [Alert]) async {
        for alert in alerts {
            await deliver(alert)
        }
    }

    private func sendNotification(_ alert: Alert) async {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.categoryIdentifier = "AIRCRAFT_ALERT"

        // Set sound based on priority
        switch alert.priority {
        case .critical:
            content.sound = .defaultCritical
            content.interruptionLevel = .critical
        case .high:
            content.sound = .default
            content.interruptionLevel = .timeSensitive
        case .normal:
            content.sound = .default
            content.interruptionLevel = .active
        case .low:
            content.sound = nil
            content.interruptionLevel = .passive
        }

        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to deliver notification: \(error)")
        }
    }

    private func playSound(_ sound: AlertSound) {
        guard let soundName = sound.systemSoundName else { return }

        if let soundURL = NSSound(named: NSSound.Name(soundName)) {
            soundURL.play()
        }
    }
}
