import SwiftUI

@main
struct TerminalManagerApp: App {
    var body: some Scene {
        MenuBarExtra("TerminalManager", systemImage: "terminal") {
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        
        Settings {
            Text("Settings Placeholder")
                .frame(width: 400, height: 300)
        }
    }
}
