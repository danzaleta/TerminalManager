# TerminalManager

A native macOS application and Desktop Widget built with Swift and SwiftUI to audit, inspect, and manage Homebrew packages (formulae and casks) and macOS GUI applications.

Designed to be lightweight, responsive, and completely buildable from the terminal using the Swift Package Manager CLI without requiring the Xcode IDE.

---

## Features

- **Installed Formulae & Casks Management**:
  - Automatically locates your Homebrew installation (`/opt/homebrew` on Apple Silicon, `/usr/local/Homebrew` on Intel).
  - Inspects all installed formulae and casks, their dependencies, versions, descriptions, and pinned status.
  - Calculates physical disk usage per package and aggregate disk consumption across all casks and formulae.
- **Safe Uninstallation**:
  - Displays confirmation dialog before destructive actions.
  - Detects and removes corresponding `.app` bundles from `/Applications` and `~/Applications`.
  - Runs automatic dependency pruning (`brew autoremove`) to keep the system clean.
- **Backup, Export & Import Checklist**:
  - Export full installation inventory to JSON for migration or backup.
  - Import checklist allowing selective or batch re-installation of packages.
- **macOS Desktop & Notification Center Widget**:
  - Native WidgetKit extension supporting `systemSmall` and `systemMedium` families.
  - Monitors total audited disk space, installed applications count, and package count right on your macOS desktop.
  - Updates automatically or on demand when package state changes in the main app.
- **Cooperative Concurrency & Streaming Logs**:
  - Async/await architecture using Swift concurrency.
  - Real-time command streaming (`ProcessRunner`) with dismissable terminal log sheet for long-running operations.

---

## Requirements

- **Operating System**: macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia).
- **Architecture**: Apple Silicon (arm64) or Intel (x86_64).
- **Tools**: Swift 6.0+ / Xcode Command Line Tools (`xcode-select --install`).
- **Dependencies**: Homebrew installed.

---

## Quick Start (Build & Install)

The project includes an automated build and packaging script (`build.sh`):

```bash
# Clone the repository
git clone https://github.com/danzaleta/TerminalManager.git
cd TerminalManager

# Build, assemble bundle, codesign, and install into /Applications
./build.sh
```

### What `build.sh` Does:
1. Compiles both the main app target and the widget target in release mode (`swift build -c release`).
2. Configures the macOS `.app` bundle at `.build/release/TerminalManager.app`.
3. Assembles the WidgetKit extension into `Contents/PlugIns/TerminalManagerWidget.appex`.
4. Codesigns the extension with Sandbox entitlements and ad-hoc signs the main bundle.
5. Installs the application to `/Applications/TerminalManager.app`.
6. Registers the app with LaunchServices (`lsregister`) and PlugInKit (`pluginkit`).
7. Flushes `chronod` and `NotificationCenter` so the widget appears immediately in the widget gallery.

---

## Adding the Desktop Widget

1. Open `/Applications/TerminalManager.app` once to complete an initial package audit.
2. Right-click on your macOS Desktop and select **Edit Widgets...** (or open Notification Center and scroll down to **Edit Widgets**).
3. Search for **Terminal Manager** in the widget gallery.
4. Drag either the **Small** or **Medium** widget onto your desktop or Notification Center.

---

## Project Structure

```text
TerminalManager/
├── Package.swift                    # SPM manifest defining TerminalManager & TerminalManagerWidget targets
├── build.sh                         # Release build, bundle packaging, codesigning & installation script
├── Info.plist                       # Main App bundle property list
├── TerminalManagerWidget-Info.plist # WidgetKit extension property list (XPC! / com.apple.widgetkit-extension)
├── TerminalManagerWidget.entitlements # App Sandbox & storage exceptions for widget
├── Sources/
│   ├── TerminalManager/             # Main Application
│   │   ├── TerminalManager.swift    # App entry point (@main App)
│   │   ├── ContentView.swift        # Main UI shell (NavigationSplitView)
│   │   ├── PackagesView.swift       # Package list, search, uninstall modal, live logs
│   │   ├── PackageModel.swift       # Decodable models for brew info JSON
│   │   ├── DependencyGraph.swift    # Tree structure for dependencies and sizes
│   │   ├── ProcessRunner.swift      # Async non-blocking Process execution & streaming
│   │   ├── BrewLocator.swift        # Locates brew binary across architectures
│   │   ├── BrewQueue.swift          # Serial execution queue for brew operations
│   │   ├── BackupManager.swift      # JSON export / import logic
│   │   └── WidgetData.swift         # Shared data model & cache persistence
│   └── TerminalManagerWidget/       # Desktop Widget Extension
│       ├── TerminalManagerWidget.swift # WidgetKit TimelineProvider, EntryView, WidgetBundle
│       └── WidgetData.swift         # Shared data model reader
```

---

## Development

Run tests:
```bash
swift test
```

Build debug version:
```bash
swift build
```

Run directly during development:
```bash
swift run TerminalManager
```

---

## AI Agent Integration

For autonomous AI coding assistants, subagents, or automated workflows looking to extend this project, see [AGENT_GUIDE.md](file:///Volumes/KINGSTON/Projects/TerminalManager/AGENT_GUIDE.md).

---

## License

MIT License. Feel free to use and modify.
