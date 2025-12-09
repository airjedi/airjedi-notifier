import SwiftUI

struct SourcesSettingsView: View {
    @ObservedObject var settings: SettingsManager
    @State private var selectedSourceId: UUID?
    @State private var showingAddSheet = false
    @State private var editingSource: SourceConfig?

    var body: some View {
        HSplitView {
            // Source list
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedSourceId) {
                    ForEach(settings.sources) { source in
                        SourceRowView(source: source)
                            .tag(source.id)
                    }
                    .onMove { from, to in
                        settings.moveSource(from: from, to: to)
                    }
                }
                .listStyle(.bordered)

                // Add/Remove buttons
                HStack {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedSourceId == nil)
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 200, maxWidth: 250)

            // Detail view
            if let sourceId = selectedSourceId,
               let source = settings.sources.first(where: { $0.id == sourceId }) {
                SourceDetailView(source: source, settings: settings)
            } else {
                VStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a source or add a new one")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSourceSheet(settings: settings, isPresented: $showingAddSheet)
        }
    }

    private func deleteSelected() {
        if let id = selectedSourceId {
            settings.deleteSource(id: id)
            selectedSourceId = nil
        }
    }
}

struct SourceRowView: View {
    let source: SourceConfig

    var body: some View {
        HStack {
            Image(systemName: source.isEnabled ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .foregroundColor(source.isEnabled ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(source.name)
                    .fontWeight(.medium)
                Text(source.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SourceDetailView: View {
    let source: SourceConfig
    @ObservedObject var settings: SettingsManager
    @State private var editedSource: SourceConfig

    init(source: SourceConfig, settings: SettingsManager) {
        self.source = source
        self.settings = settings
        self._editedSource = State(initialValue: source)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $editedSource.name)
                Picker("Type", selection: $editedSource.type) {
                    ForEach(SourceType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                TextField("Host", text: $editedSource.host)
                TextField("Port", value: $editedSource.port, format: .number)
                Toggle("Enabled", isOn: $editedSource.isEnabled)
            }

            Section {
                HStack {
                    Text("Connection URL:")
                        .foregroundColor(.secondary)
                    Text(editedSource.urlString)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: editedSource) { newValue in
            settings.updateSource(newValue)
        }
        .onChange(of: source) { newValue in
            editedSource = newValue
        }
    }
}

struct AddSourceSheet: View {
    @ObservedObject var settings: SettingsManager
    @Binding var isPresented: Bool
    @State private var name = "New Source"
    @State private var type: SourceType = .dump1090
    @State private var host = "localhost"
    @State private var port = 8080

    var body: some View {
        VStack(spacing: 16) {
            Text("Add ADS-B Source")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $type) {
                    ForEach(SourceType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: type) { newType in
                    port = newType.defaultPort
                }
                TextField("Host", text: $host)
                TextField("Port", value: $port, format: .number)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Add") {
                    let newSource = SourceConfig(
                        name: name,
                        type: type,
                        host: host,
                        port: port,
                        priority: settings.sources.count
                    )
                    settings.addSource(newSource)
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350, height: 280)
    }
}

#Preview {
    SourcesSettingsView(settings: SettingsManager.shared)
        .frame(width: 500, height: 350)
}
