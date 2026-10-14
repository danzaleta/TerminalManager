# AI Agent & Subagent Architecture Guide

This document is specifically crafted for **Autonomous AI Coding Agents** (and human engineers) working on, maintaining, or expanding the **TerminalManager** codebase.

It documents the system architecture, design patterns, hidden system quirks, and conventions required to safely extend the application without breaking macOS sandbox, system daemons (`chronod`, `launchd`), or Swift concurrency pools.

---

## 1. System Overview & Core Invariants

### Invariant 1: Pure SPM CLI Build (Zero `.xcodeproj` Reliance)
The project **must** remain compilable and deployable via the CLI without Xcode IDE (`swift build -c release`).
- Bundle assembly, `.appex` plugin packaging, codesigning, and registration are managed by [`build.sh`](file:///Volumes/KINGSTON/Projects/TerminalManager/build.sh).
- When modifying targets, frameworks, or dependencies, update [`Package.swift`](file:///Volumes/KINGSTON/Projects/TerminalManager/Package.swift) directly.

### Invariant 2: WidgetKit Entry Point Contract (`-e _NSExtensionMain`)
Standard SwiftPM `.executableTarget` creates an executable whose Mach-O header (`LC_MAIN`) points directly to the Swift `@main` runtime `_main`.
**CRITICAL**: On macOS 14+ (Sonoma/Sequoia), WidgetKit extensions run on top of `ExtensionKit` / `ExtensionFoundation`.
If execution starts at `_main` instead of `NSExtensionMain`:
- `ExtensionFoundation` never configures `ExtensionMain.shared`.
- When `WidgetKit` attempts to access `_EXRunningExtension._shared`, it hits a `SIGTRAP` (`brk #1`) in `ExtensionFoundation` at offset `0x22aee5d18`.
- **Rule**: [`Package.swift`](file:///Volumes/KINGSTON/Projects/TerminalManager/Package.swift) must always include:
  ```swift
  linkerSettings: [
      .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
  ]
  ```
  in the `TerminalManagerWidget` target. Do **not** remove this flag.

### Invariant 3: Swift Concurrency & Process Isolation
Never execute synchronous blocking calls like `process.waitUntilExit()` on the default Swift Concurrency cooperative thread pool.
- Doing so can starve the limited thread pool, leading to UI hangs and deadlock during pipe reading.
- Always use the asynchronous, non-blocking [`ProcessRunner`](file:///Volumes/KINGSTON/Projects/TerminalManager/Sources/TerminalManager/ProcessRunner.swift), which uses `withCheckedContinuation`, process termination handlers, and detached background tasks to read standard output and standard error concurrently.

---

## 2. Directory Layout & Key Components

```text
TerminalManager/
├── Package.swift                             # Targets: TerminalManager, TerminalManagerWidget, TerminalManagerTests
├── build.sh                                  # Build, packaging, codesigning, install & daemon refresh script
├── Info.plist                                # App metadata & LSMinimumSystemVersion
├── TerminalManagerWidget-Info.plist          # CFBundlePackageType=XPC!, com.apple.widgetkit-extension
├── TerminalManagerWidget.entitlements        # Sandboxing & file-read temporary exceptions
├── Sources/
│   ├── TerminalManager/                      # Main Application
│   │   ├── TerminalManager.swift             # @main App struct, WindowGroup & menu definitions
│   │   ├── ContentView.swift                 # Root NavigationSplitView
│   │   ├── PackagesView.swift                # State machine for audits, search, selection, uninstall, log sheet
│   │   ├── PackageModel.swift                # Decodables for `brew info --json=v2 --installed`
│   │   ├── DependencyGraph.swift             # Calculates dependencies, reverse deps, and app sizes
│   │   ├── ProcessRunner.swift               # Async process execution & AsyncThrowingStream
│   │   ├── BrewLocator.swift                 # Discovers brew binary on Apple Silicon vs Intel
│   │   ├── BrewQueue.swift                   # Serial queue actor for package mutations
│   │   ├── BackupManager.swift               # Export & Import checklist JSON models
│   │   └── WidgetData.swift                  # Shared data struct & disk cache read/write
│   └── TerminalManagerWidget/                # macOS Desktop Widget
│       ├── TerminalManagerWidget.swift       # WidgetBundle, TimelineProvider, Small & Medium SwiftUI views
│       └── WidgetData.swift                  # Identical WidgetData copy for widget target
```

---

## 3. Data Flow & Inter-Process Communication (IPC)

Because the widget runs in an App Extension process (`.appex`) managed by `chronod` under App Sandbox restrictions, data is exchanged via serialized JSON on disk:

```
+-----------------------------------+
|       TerminalManager.app         |
|  - Audits Homebrew & Casks        |
|  - Calculates total disk usage    |
+-----------------+-----------------+
                  |
                  | 1. Writes WidgetData
                  v
+-----------------------------------+
|  ~/Library/Application Support/   |
|  TerminalManager/widget_data.json |
+-----------------+-----------------+
                  ^
                  | 2. Reads on Timeline reload
+-----------------+-----------------+
|   TerminalManagerWidget.appex     |
|   - Provider.getTimeline()        |
|   - Renders desktop SwiftUI view  |
+-----------------------------------+
```

### Refresh Protocol:
When package mutations or audits complete in [`PackagesView.swift`](file:///Volumes/KINGSTON/Projects/TerminalManager/Sources/TerminalManager/PackagesView.swift):
1. Compute aggregate statistics: `appsCount`, `packagesCount`, `totalBytes`, `formattedDiskSpace`.
2. Instantiate and save `WidgetData.init(...).save()`.
3. Optionally notify WidgetKit via `WidgetCenter.shared.reloadAllTimelines()` (or `killall chronod` during CLI rebuilds).

---

## 4. Expansion Vectors & How to Add Features

### Vector A: Supporting Other Package Managers (e.g., `mas`, `npm`, `pip`/`uv`, `cargo`)
To add a new package manager:
1. Create a locator conforming to a unified locator interface (e.g. `MasLocator.swift` looking up `/opt/homebrew/bin/mas` or `/usr/local/bin/mas`).
2. Add a model representing the foreign package (conforming to `Identifiable`, `Sendable`, and `Codable`).
3. Add a dedicated section or tab in `ContentView.swift` and `PackagesView.swift`.
4. Include the discovered disk footprint into `WidgetData.totalBytes` so the desktop widget reflects the combined disk consumption.

### Vector B: Adding Interactive AppIntents to the Widget
macOS 14+ supports interactive widgets via `AppIntent`:
1. In `TerminalManagerWidget.swift`, define an intent conforming to `AppIntent`:
   ```swift
   import AppIntents

   struct AuditPackagesIntent: AppIntent {
       static var title: LocalizedStringResource = "Run Package Audit"
       func perform() async throws -> some IntentResult {
           // Trigger background task or notify main app
           return .result()
       }
   }
   ```
2. Embed a `Button(intent: AuditPackagesIntent())` in `TerminalManagerWidgetEntryView`.

### Vector C: Migrating from File-Based Cache to Shared App Groups
If the app is later signed with a paid Apple Developer Team ID:
1. Enable `com.apple.security.application-groups` with `group.com.danzaleta.terminalmanager` in both app entitlements and `TerminalManagerWidget.entitlements`.
2. Update `WidgetData.storageURL` to:
   ```swift
   FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.danzaleta.terminalmanager")?
       .appendingPathComponent("widget_data.json")
   ```

---

## 5. Diagnostic & Troubleshooting Playbook

When debugging issues during agent execution, use these precise terminal commands:

### Diagnosing Widget Registration & System Daemons:
```bash
# Verify plugin is indexed by LaunchServices and PlugInKit
pluginkit -m -v -i com.danzaleta.terminalmanager.widget

# Inspect chronod (WidgetKit daemon) live log events
/usr/bin/log show --predicate 'process == "TerminalManagerWidget" || (process == "chronod" && eventMessage CONTAINS[c] "terminalmanager")' --last 2m

# Check for extension crashes
ls -lt ~/Library/Logs/DiagnosticReports/TerminalManagerWidget* | head -n 5
```

### Expected Successful `chronod` Log Pattern:
When everything is working properly, `/usr/bin/log` should report:
```text
chronod: (WidgetKit) Session operation: `getAllDescriptors` executing.
chronod: (ChronoCore) Completed precaching placeholders for <CHSWidgetDescriptor: ... kind: TerminalManagerWidget; supportedFamilies: "(systemSmall, systemMedium)">; 0 active reloads; 0 pending descriptors
```
If `chronod` reports `SIGTRAP` or `connection was invalidated`, verify `_NSExtensionMain` in `otool -l <widget_binary> | grep -A 5 LC_MAIN`.

### Testing Build Integrity:
```bash
# Full test suite
swift test

# Build and verify packaging
./build.sh
```
