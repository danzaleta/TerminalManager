import SwiftUI

@main
struct TerminalManagerApp: App {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        MenuBarExtra("TerminalManager", systemImage: "terminal") {
            Button("Settings") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        
        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}
