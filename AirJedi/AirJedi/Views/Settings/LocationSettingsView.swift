import SwiftUI

struct LocationSettingsView: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Text("Location settings placeholder")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
