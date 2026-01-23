import Foundation
import UserNotifications
import AppKit

@MainActor
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published private(set) var isAuthorized = false
    @Published var alertsEnabled = true

    // Action identifiers
    static let showInListActionIdentifier = "SHOW_IN_LIST"
    static let aircraftAlertCategoryIdentifier = "AIRCRAFT_ALERT"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
        checkAuthorization()
    }

    // MARK: - Category Registration

    private func registerNotificationCategories() {
        let showInListAction = UNNotificationAction(
            identifier: Self.showInListActionIdentifier,
            title: "Show in List",
            options: [.foreground]
        )

        let aircraftCategory = UNNotificationCategory(
            identifier: Self.aircraftAlertCategoryIdentifier,
            actions: [showInListAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([aircraftCategory])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when app is in foreground (menu bar apps need this)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification action responses
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case Self.showInListActionIdentifier, UNNotificationDefaultActionIdentifier:
            // User tapped "Show in List" or the notification itself
            // Post notification to open menu bar popup
            Task { @MainActor in
                NotificationCenter.default.post(name: .showAircraftList, object: nil)
            }
        default:
            break
        }
        completionHandler()
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

        // Play in-app sound
        playSound(alert.sound)

        // Send desktop notification if authorized and enabled for this alert
        if isAuthorized && alert.sendNotification {
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
        if let subtitle = alert.subtitle {
            content.subtitle = subtitle
        }
        content.body = alert.body
        content.categoryIdentifier = Self.aircraftAlertCategoryIdentifier

        // Set interruption level based on priority
        // Note: .critical requires a special entitlement, so we use .timeSensitive as max
        switch alert.priority {
        case .critical, .high:
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
        guard !SettingsManager.shared.soundsMuted else { return }
        guard let soundName = sound.systemSoundName else { return }

        if let soundURL = NSSound(named: NSSound.Name(soundName)) {
            soundURL.play()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showAircraftList = Notification.Name("showAircraftList")
}
