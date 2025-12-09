import SwiftUI

@main
struct AirJediApp: App {
    var body: some Scene {
        MenuBarExtra("AirJedi", systemImage: "airplane") {
            Text("AirJedi")
                .padding()
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
