import SwiftUI

@main
struct TerminalManagerApp: App {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        MenuBarExtra("TerminalManager", systemImage: "terminal") {
            let data = WidgetData.load()
            if let d = data {
                Text("Disk Usage: \(d.formattedDiskSpace)")
                    .font(.caption)
                Text("\(d.appsCount) Apps · \(d.packagesCount) Packages")
                    .font(.caption)
                Divider()
            }
            
            Button("Open Manager...") {
                openWindow(id: "manager")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o", modifiers: .command)
            
            Divider()
            
            Button("Quit TerminalManager") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        
        Window("Terminal Manager", id: "manager") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}
