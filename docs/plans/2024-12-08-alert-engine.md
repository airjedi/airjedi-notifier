# Alert Engine Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a configurable alert system that notifies users about interesting aircraft, proximity events, emergency squawks, and specific aircraft types.

**Architecture:** AlertRule protocol with concrete implementations. AlertEngine evaluates rules against aircraft updates. NotificationManager delivers alerts via macOS notifications, sounds, and visual feedback.

**Tech Stack:** Swift 5.9+, UserNotifications, AVFoundation, Combine

---

## Task 1: Create Alert Models

**Files:**
- Create: `AirJedi/AirJedi/Models/AlertModels.swift`

**Step 1: Create the alert types and protocol**

Create file `AirJedi/AirJedi/Models/AlertModels.swift`:

```swift
import Foundation

// MARK: - Alert Priority

enum AlertPriority: String, Codable, CaseIterable, Identifiable {
    case low
    case normal
    case high
    case critical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Alert Sound

enum AlertSound: String, Codable, CaseIterable, Identifiable {
    case none
    case subtle
    case standard
    case prominent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .subtle: return "Subtle"
        case .standard: return "Standard"
        case .prominent: return "Prominent"
        }
    }

    var systemSoundName: String? {
        switch self {
        case .none: return nil
        case .subtle: return "Pop"
        case .standard: return "Glass"
        case .prominent: return "Hero"
        }
    }
}

// MARK: - Alert

struct Alert: Identifiable {
    let id: UUID
    let aircraft: Aircraft
    let ruleId: UUID
    let ruleName: String
    let title: String
    let body: String
    let priority: AlertPriority
    let sound: AlertSound
    let timestamp: Date

    init(
        aircraft: Aircraft,
        ruleId: UUID,
        ruleName: String,
        title: String,
        body: String,
        priority: AlertPriority,
        sound: AlertSound
    ) {
        self.id = UUID()
        self.aircraft = aircraft
        self.ruleId = ruleId
        self.ruleName = ruleName
        self.title = title
        self.body = body
        self.priority = priority
        self.sound = sound
        self.timestamp = Date()
    }
}

// MARK: - Alert Rule Type

enum AlertRuleType: String, Codable, CaseIterable, Identifiable {
    case proximity
    case watchlist
    case squawk
    case aircraftType

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .proximity: return "Proximity"
        case .watchlist: return "Watchlist"
        case .squawk: return "Emergency Squawk"
        case .aircraftType: return "Aircraft Type"
        }
    }

    var icon: String {
        switch self {
        case .proximity: return "location.circle"
        case .watchlist: return "star.circle"
        case .squawk: return "exclamationmark.triangle"
        case .aircraftType: return "airplane.circle"
        }
    }
}

// MARK: - Alert Rule (Codable wrapper)

struct AlertRuleConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: AlertRuleType
    var isEnabled: Bool
    var priority: AlertPriority
    var sound: AlertSound

    // Proximity settings
    var maxDistanceNm: Double?
    var maxAltitudeFeet: Int?
    var minAltitudeFeet: Int?

    // Watchlist settings
    var watchCallsigns: [String]?
    var watchRegistrations: [String]?
    var watchIcaoHex: [String]?

    // Squawk settings
    var squawkCodes: [String]?

    // Aircraft type settings
    var typeCategories: [String]?  // "military", "helicopter", etc.
    var typeCodes: [String]?  // "C17", "F16", etc.

    init(
        id: UUID = UUID(),
        name: String,
        type: AlertRuleType,
        isEnabled: Bool = true,
        priority: AlertPriority = .normal,
        sound: AlertSound = .standard
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isEnabled = isEnabled
        self.priority = priority
        self.sound = sound
    }

    static func defaultProximityRule() -> AlertRuleConfig {
        var rule = AlertRuleConfig(name: "Nearby Aircraft", type: .proximity)
        rule.maxDistanceNm = 5.0
        rule.maxAltitudeFeet = 10000
        return rule
    }

    static func defaultSquawkRule() -> AlertRuleConfig {
        var rule = AlertRuleConfig(name: "Emergency Squawks", type: .squawk, priority: .critical, sound: .prominent)
        rule.squawkCodes = ["7500", "7600", "7700"]
        return rule
    }
}
```

**Step 2: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Models/AlertModels.swift
git commit -m "Add alert models and rule configuration types"
```

---

## Task 2: Create AlertEngine

**Files:**
- Create: `AirJedi/AirJedi/Services/AlertEngine.swift`

**Step 1: Create the alert evaluation engine**

Create file `AirJedi/AirJedi/Services/AlertEngine.swift`:

```swift
import Foundation
import Combine

@MainActor
class AlertEngine: ObservableObject {
    @Published private(set) var recentAlerts: [Alert] = []
    @Published var alertRules: [AlertRuleConfig] = []

    private let settings = SettingsManager.shared
    private var cooldowns: [String: Date] = [:]  // icaoHex -> lastAlerted
    private var previousAircraftState: [String: Aircraft] = [:]

    var cooldownSeconds: TimeInterval = 300  // 5 minutes

    init() {
        loadRules()
    }

    // MARK: - Rule Management

    func loadRules() {
        if let data = UserDefaults.standard.data(forKey: "alertRules"),
           let rules = try? JSONDecoder().decode([AlertRuleConfig].self, from: data) {
            alertRules = rules
        }
    }

    func saveRules() {
        if let data = try? JSONEncoder().encode(alertRules) {
            UserDefaults.standard.set(data, forKey: "alertRules")
        }
    }

    func addRule(_ rule: AlertRuleConfig) {
        alertRules.append(rule)
        saveRules()
    }

    func updateRule(_ rule: AlertRuleConfig) {
        if let index = alertRules.firstIndex(where: { $0.id == rule.id }) {
            alertRules[index] = rule
            saveRules()
        }
    }

    func deleteRule(id: UUID) {
        alertRules.removeAll { $0.id == id }
        saveRules()
    }

    // MARK: - Evaluation

    func evaluate(aircraft: [Aircraft]) -> [Alert] {
        let enabledRules = alertRules.filter { $0.isEnabled }
        guard !enabledRules.isEmpty else { return [] }

        var newAlerts: [Alert] = []
        let referenceLocation = settings.referenceLocation

        for ac in aircraft {
            // Check cooldown
            if let lastAlert = cooldowns[ac.icaoHex],
               Date().timeIntervalSince(lastAlert) < cooldownSeconds {
                continue
            }

            for rule in enabledRules {
                if let alert = evaluateRule(rule, aircraft: ac, referenceLocation: referenceLocation) {
                    newAlerts.append(alert)
                    cooldowns[ac.icaoHex] = Date()
                    break  // One alert per aircraft per evaluation
                }
            }
        }

        // Update previous state
        for ac in aircraft {
            previousAircraftState[ac.icaoHex] = ac
        }

        // Add to recent alerts (keep last 50)
        recentAlerts.insert(contentsOf: newAlerts, at: 0)
        if recentAlerts.count > 50 {
            recentAlerts = Array(recentAlerts.prefix(50))
        }

        return newAlerts
    }

    private func evaluateRule(_ rule: AlertRuleConfig, aircraft: Aircraft, referenceLocation: Coordinate) -> Alert? {
        switch rule.type {
        case .proximity:
            return evaluateProximity(rule, aircraft: aircraft, referenceLocation: referenceLocation)
        case .watchlist:
            return evaluateWatchlist(rule, aircraft: aircraft)
        case .squawk:
            return evaluateSquawk(rule, aircraft: aircraft)
        case .aircraftType:
            return evaluateAircraftType(rule, aircraft: aircraft)
        }
    }

    // MARK: - Rule Evaluators

    private func evaluateProximity(_ rule: AlertRuleConfig, aircraft: Aircraft, referenceLocation: Coordinate) -> Alert? {
        guard let maxDistance = rule.maxDistanceNm,
              let distance = aircraft.distance(from: referenceLocation),
              distance <= maxDistance else {
            return nil
        }

        // Check altitude bounds if specified
        if let maxAlt = rule.maxAltitudeFeet,
           let alt = aircraft.altitudeFeet,
           alt > maxAlt {
            return nil
        }

        if let minAlt = rule.minAltitudeFeet,
           let alt = aircraft.altitudeFeet,
           alt < minAlt {
            return nil
        }

        // Check if this is a new detection (wasn't within range before)
        if let previous = previousAircraftState[aircraft.icaoHex],
           let prevDistance = previous.distance(from: referenceLocation),
           prevDistance <= maxDistance {
            return nil  // Already was in range
        }

        let callsign = aircraft.callsign ?? aircraft.icaoHex
        let altText = aircraft.altitudeFeet.map { "\($0)ft" } ?? "unknown alt"

        return Alert(
            aircraft: aircraft,
            ruleId: rule.id,
            ruleName: rule.name,
            title: "Aircraft Nearby",
            body: "\(callsign) at \(String(format: "%.1f", distance))nm, \(altText)",
            priority: rule.priority,
            sound: rule.sound
        )
    }

    private func evaluateWatchlist(_ rule: AlertRuleConfig, aircraft: Aircraft) -> Alert? {
        var matched = false
        var matchReason = ""

        if let callsigns = rule.watchCallsigns,
           let callsign = aircraft.callsign,
           callsigns.contains(where: { callsign.uppercased().contains($0.uppercased()) }) {
            matched = true
            matchReason = "Callsign match: \(callsign)"
        }

        if let registrations = rule.watchRegistrations,
           let reg = aircraft.registration,
           registrations.contains(where: { reg.uppercased() == $0.uppercased() }) {
            matched = true
            matchReason = "Registration match: \(reg)"
        }

        if let icaos = rule.watchIcaoHex,
           icaos.contains(where: { aircraft.icaoHex.uppercased() == $0.uppercased() }) {
            matched = true
            matchReason = "ICAO match: \(aircraft.icaoHex)"
        }

        guard matched else { return nil }

        // Only alert on first detection
        if previousAircraftState[aircraft.icaoHex] != nil {
            return nil
        }

        let callsign = aircraft.callsign ?? aircraft.icaoHex

        return Alert(
            aircraft: aircraft,
            ruleId: rule.id,
            ruleName: rule.name,
            title: "Watchlist Aircraft",
            body: "\(callsign) - \(matchReason)",
            priority: rule.priority,
            sound: rule.sound
        )
    }

    private func evaluateSquawk(_ rule: AlertRuleConfig, aircraft: Aircraft) -> Alert? {
        guard let codes = rule.squawkCodes,
              let squawk = aircraft.squawk,
              codes.contains(squawk) else {
            return nil
        }

        // Check if squawk changed (new emergency)
        if let previous = previousAircraftState[aircraft.icaoHex],
           previous.squawk == squawk {
            return nil
        }

        let callsign = aircraft.callsign ?? aircraft.icaoHex
        let squawkMeaning: String
        switch squawk {
        case "7500": squawkMeaning = "HIJACK"
        case "7600": squawkMeaning = "RADIO FAILURE"
        case "7700": squawkMeaning = "EMERGENCY"
        default: squawkMeaning = "Code \(squawk)"
        }

        return Alert(
            aircraft: aircraft,
            ruleId: rule.id,
            ruleName: rule.name,
            title: "⚠️ \(squawkMeaning)",
            body: "\(callsign) squawking \(squawk)",
            priority: rule.priority,
            sound: rule.sound
        )
    }

    private func evaluateAircraftType(_ rule: AlertRuleConfig, aircraft: Aircraft) -> Alert? {
        var matched = false

        if let typeCodes = rule.typeCodes,
           let typeCode = aircraft.aircraftTypeCode,
           typeCodes.contains(where: { typeCode.uppercased().contains($0.uppercased()) }) {
            matched = true
        }

        // For categories, we'd need enrichment data - skip for now
        // if let categories = rule.typeCategories { ... }

        guard matched else { return nil }

        // Only alert on first detection
        if previousAircraftState[aircraft.icaoHex] != nil {
            return nil
        }

        let callsign = aircraft.callsign ?? aircraft.icaoHex
        let typeCode = aircraft.aircraftTypeCode ?? "Unknown"

        return Alert(
            aircraft: aircraft,
            ruleId: rule.id,
            ruleName: rule.name,
            title: "Aircraft Type Match",
            body: "\(callsign) - \(typeCode)",
            priority: rule.priority,
            sound: rule.sound
        )
    }

    // MARK: - Cooldown Management

    func clearCooldowns() {
        cooldowns.removeAll()
    }

    func clearAlerts() {
        recentAlerts.removeAll()
    }
}
```

**Step 2: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Services/AlertEngine.swift
git commit -m "Add AlertEngine for rule evaluation"
```

---

## Task 3: Create NotificationManager

**Files:**
- Create: `AirJedi/AirJedi/Services/NotificationManager.swift`

**Step 1: Create the notification delivery service**

Create file `AirJedi/AirJedi/Services/NotificationManager.swift`:

```swift
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
```

**Step 2: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/Services/NotificationManager.swift
git commit -m "Add NotificationManager for alert delivery"
```

---

## Task 4: Wire AlertEngine to AppState

**Files:**
- Modify: `AirJedi/AirJedi/App/AppState.swift`

**Step 1: Add AlertEngine and wire up evaluation**

Add to AppState.swift:

```swift
import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isConnecting = false

    let aircraftService: AircraftService
    let providerManager: ProviderManager
    let alertEngine: AlertEngine
    let notificationManager: NotificationManager

    private let settings = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    var aircraft: [Aircraft] {
        aircraftService.aircraft
    }

    var nearbyCount: Int {
        aircraftService.aircraft.count
    }

    var referenceLocation: Coordinate {
        settings.referenceLocation
    }

    var connectionStatus: ProviderStatus {
        providerManager.combinedStatus
    }

    var recentAlerts: [Alert] {
        alertEngine.recentAlerts
    }

    var hasRecentAlert: Bool {
        if let mostRecent = alertEngine.recentAlerts.first {
            return Date().timeIntervalSince(mostRecent.timestamp) < 30
        }
        return false
    }

    init() {
        self.aircraftService = AircraftService()
        self.providerManager = ProviderManager(aircraftService: aircraftService)
        self.alertEngine = AlertEngine()
        self.notificationManager = NotificationManager.shared

        // Forward changes from services
        aircraftService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.evaluateAlerts()
            }
            .store(in: &cancellables)

        providerManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        alertEngine.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Request notification permission
        Task {
            await notificationManager.requestPermission()
        }

        // Auto-start providers
        Task {
            await startProviders()
        }
    }

    func startProviders() async {
        isConnecting = true
        await providerManager.startAll()
        isConnecting = false
    }

    func stopProviders() async {
        await providerManager.stopAll()
    }

    func restartProviders() async {
        isConnecting = true
        await providerManager.restart()
        isConnecting = false
    }

    private func evaluateAlerts() {
        let newAlerts = alertEngine.evaluate(aircraft: aircraftService.aircraft)
        if !newAlerts.isEmpty {
            Task {
                await notificationManager.deliverMultiple(newAlerts)
            }
        }
    }
}
```

**Step 2: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AirJedi/AirJedi/App/AppState.swift
git commit -m "Wire AlertEngine and NotificationManager to AppState"
```

---

## Task 5: Create Alerts Settings Tab

**Files:**
- Modify: `AirJedi/AirJedi/Views/Settings/SettingsView.swift`
- Create: `AirJedi/AirJedi/Views/Settings/AlertsSettingsView.swift`

**Step 1: Create AlertsSettingsView**

Create file `AirJedi/AirJedi/Views/Settings/AlertsSettingsView.swift`:

```swift
import SwiftUI

struct AlertsSettingsView: View {
    @StateObject private var alertEngine = AlertEngine()
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var selectedRuleId: UUID?
    @State private var showingAddSheet = false

    var body: some View {
        HSplitView {
            // Rule list
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedRuleId) {
                    ForEach(alertEngine.alertRules) { rule in
                        AlertRuleRowView(rule: rule)
                            .tag(rule.id)
                    }
                }
                .listStyle(.bordered)

                HStack {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedRuleId == nil)
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 200, maxWidth: 250)

            // Detail view
            if let ruleId = selectedRuleId,
               let rule = alertEngine.alertRules.first(where: { $0.id == ruleId }) {
                AlertRuleDetailView(rule: rule, alertEngine: alertEngine)
            } else {
                VStack(spacing: 12) {
                    if !notificationManager.isAuthorized {
                        VStack(spacing: 8) {
                            Image(systemName: "bell.slash")
                                .font(.system(size: 32))
                                .foregroundColor(.orange)
                            Text("Notifications Disabled")
                                .font(.headline)
                            Text("Enable in System Settings to receive alerts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Open System Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                            }
                        }
                    } else {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Select a rule or add a new one")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddAlertRuleSheet(alertEngine: alertEngine, isPresented: $showingAddSheet)
        }
    }

    private func deleteSelected() {
        if let id = selectedRuleId {
            alertEngine.deleteRule(id: id)
            selectedRuleId = nil
        }
    }
}

struct AlertRuleRowView: View {
    let rule: AlertRuleConfig

    var body: some View {
        HStack {
            Image(systemName: rule.type.icon)
                .foregroundColor(rule.isEnabled ? .accentColor : .secondary)
            VStack(alignment: .leading) {
                Text(rule.name)
                    .fontWeight(.medium)
                Text(rule.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !rule.isEnabled {
                Text("Off")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AlertRuleDetailView: View {
    let rule: AlertRuleConfig
    @ObservedObject var alertEngine: AlertEngine
    @State private var editedRule: AlertRuleConfig

    init(rule: AlertRuleConfig, alertEngine: AlertEngine) {
        self.rule = rule
        self.alertEngine = alertEngine
        self._editedRule = State(initialValue: rule)
    }

    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $editedRule.name)
                Toggle("Enabled", isOn: $editedRule.isEnabled)
                Picker("Priority", selection: $editedRule.priority) {
                    ForEach(AlertPriority.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                Picker("Sound", selection: $editedRule.sound) {
                    ForEach(AlertSound.allCases) { sound in
                        Text(sound.displayName).tag(sound)
                    }
                }
            }

            ruleSpecificSettings
        }
        .formStyle(.grouped)
        .onChange(of: editedRule) { newValue in
            alertEngine.updateRule(newValue)
        }
        .onChange(of: rule) { newValue in
            editedRule = newValue
        }
    }

    @ViewBuilder
    private var ruleSpecificSettings: some View {
        switch editedRule.type {
        case .proximity:
            Section("Proximity Settings") {
                HStack {
                    Text("Max Distance")
                    Spacer()
                    TextField("nm", value: $editedRule.maxDistanceNm, format: .number)
                        .frame(width: 60)
                    Text("nm")
                }
                HStack {
                    Text("Max Altitude")
                    Spacer()
                    TextField("ft", value: $editedRule.maxAltitudeFeet, format: .number)
                        .frame(width: 80)
                    Text("ft")
                }
            }

        case .watchlist:
            Section("Watchlist") {
                Text("Callsigns (comma-separated)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., UAL, DAL, N123AB", text: watchlistCallsignsBinding)
            }

        case .squawk:
            Section("Squawk Codes") {
                Text("Emergency codes are pre-configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("7500 - Hijack")
                Text("7600 - Radio Failure")
                Text("7700 - Emergency")
            }

        case .aircraftType:
            Section("Aircraft Types") {
                Text("Type codes (comma-separated)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., C17, F16, B2", text: typeCodesBinding)
            }
        }
    }

    private var watchlistCallsignsBinding: Binding<String> {
        Binding(
            get: { editedRule.watchCallsigns?.joined(separator: ", ") ?? "" },
            set: { newValue in
                let items = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                editedRule.watchCallsigns = items.isEmpty ? nil : items
            }
        )
    }

    private var typeCodesBinding: Binding<String> {
        Binding(
            get: { editedRule.typeCodes?.joined(separator: ", ") ?? "" },
            set: { newValue in
                let items = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                editedRule.typeCodes = items.isEmpty ? nil : items
            }
        )
    }
}

struct AddAlertRuleSheet: View {
    @ObservedObject var alertEngine: AlertEngine
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var type: AlertRuleType = .proximity

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Alert Rule")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $type) {
                    ForEach(AlertRuleType.allCases) { ruleType in
                        Label(ruleType.displayName, systemImage: ruleType.icon)
                            .tag(ruleType)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Add") {
                    var rule = AlertRuleConfig(name: name.isEmpty ? type.displayName : name, type: type)

                    // Set defaults based on type
                    switch type {
                    case .proximity:
                        rule.maxDistanceNm = 5.0
                        rule.maxAltitudeFeet = 10000
                    case .squawk:
                        rule.squawkCodes = ["7500", "7600", "7700"]
                        rule.priority = .critical
                        rule.sound = .prominent
                    default:
                        break
                    }

                    alertEngine.addRule(rule)
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350, height: 200)
    }
}

#Preview {
    AlertsSettingsView()
        .frame(width: 500, height: 350)
}
```

**Step 2: Update SettingsView to use AlertsSettingsView**

In `SettingsView.swift`, replace `AlertsSettingsPlaceholder()` with `AlertsSettingsView()`:

```swift
AlertsSettingsView()
    .tabItem {
        Label(SettingsTab.alerts.rawValue, systemImage: SettingsTab.alerts.icon)
    }
    .tag(SettingsTab.alerts)
```

Also remove the `AlertsSettingsPlaceholder` struct.

**Step 3: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 4: Commit**

```bash
git add AirJedi/AirJedi/Views/Settings/
git commit -m "Add Alerts settings tab with rule configuration"
```

---

## Task 6: Update MenuBarIcon for Alert State

**Files:**
- Modify: `AirJedi/AirJedi/Views/MenuBarIcon.swift`
- Modify: `AirJedi/AirJedi/AirJediApp.swift`

**Step 1: Update MenuBarIcon to show alert state**

Update `MenuBarIcon.swift`:

```swift
import SwiftUI

struct MenuBarIcon: View {
    let aircraftCount: Int
    let status: ProviderStatus
    let hasAlert: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(iconColor)

            if hasAlert {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .offset(x: 6, y: -4)
            } else if aircraftCount > 0 && status.isConnected {
                Text("\(aircraftCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Circle().fill(Color.blue))
                    .offset(x: 6, y: -4)
            }
        }
    }

    private var iconName: String {
        switch status {
        case .error:
            return "airplane.circle.fill"
        case .disconnected:
            return "airplane"
        default:
            return "airplane"
        }
    }

    private var iconColor: Color? {
        if hasAlert {
            return .orange
        }
        switch status {
        case .error:
            return .red
        case .disconnected:
            return .secondary
        default:
            return nil
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        MenuBarIcon(aircraftCount: 0, status: .disconnected, hasAlert: false)
        MenuBarIcon(aircraftCount: 3, status: .connected(aircraftCount: 3), hasAlert: false)
        MenuBarIcon(aircraftCount: 3, status: .connected(aircraftCount: 3), hasAlert: true)
    }
    .padding()
}
```

**Step 2: Update AirJediApp to pass alert state**

Update `AirJediApp.swift`:

```swift
import SwiftUI

@main
struct AirJediApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            AircraftListView(appState: appState)
        } label: {
            MenuBarIcon(
                aircraftCount: appState.nearbyCount,
                status: appState.connectionStatus,
                hasAlert: appState.hasRecentAlert
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
```

**Step 3: Regenerate and build**

```bash
cd /Users/ccustine/development/aviation/airjedi-notifier/AirJedi
xcodegen generate
xcodebuild -project AirJedi.xcodeproj -scheme AirJedi -configuration Debug build
```

Expected: Build succeeds.

**Step 4: Commit**

```bash
git add AirJedi/AirJedi/Views/MenuBarIcon.swift
git add AirJedi/AirJedi/AirJediApp.swift
git commit -m "Update MenuBarIcon to show alert indicator"
```

---

## Summary

After completing all tasks, you will have:
- Alert models (priority, sound, rule configuration)
- AlertEngine that evaluates rules against aircraft
- NotificationManager for macOS notifications and sounds
- Full Alerts settings tab with add/edit/delete rules
- Menu bar icon with alert indicator
- Four rule types: Proximity, Watchlist, Squawk, Aircraft Type
- Cooldown system to prevent notification spam
