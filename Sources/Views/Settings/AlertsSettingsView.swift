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
            .frame(width: 150)

            // Detail view
            Group {
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
            .layoutPriority(1)
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
        ScrollView {
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
                    Toggle("Send Desktop Notification", isOn: $editedRule.sendNotification)
                }

                Section("Highlighting") {
                    Toggle("Highlight in List", isOn: hasHighlightBinding)
                    if editedRule.highlightColor != nil {
                        ColorPicker("Highlight Color", selection: highlightColorBinding, supportsOpacity: false)
                    }
                }

                ruleSpecificSettings
            }
            .formStyle(.grouped)
        }
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
                    .textFieldStyle(.roundedBorder)
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
                    .textFieldStyle(.roundedBorder)
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

    private var hasHighlightBinding: Binding<Bool> {
        Binding(
            get: { editedRule.highlightColor != nil },
            set: { newValue in
                if newValue {
                    editedRule.highlightColor = .defaultHighlight
                } else {
                    editedRule.highlightColor = nil
                }
            }
        )
    }

    private var highlightColorBinding: Binding<Color> {
        Binding(
            get: { editedRule.highlightColor?.color ?? AlertColor.defaultHighlight.color },
            set: { newValue in
                editedRule.highlightColor = AlertColor(color: newValue)
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
