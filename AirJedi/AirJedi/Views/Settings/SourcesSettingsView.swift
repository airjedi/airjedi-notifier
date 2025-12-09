import SwiftUI

struct SourcesSettingsView: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Text("Sources settings placeholder")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
