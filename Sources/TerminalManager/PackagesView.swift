import Foundation
import SwiftUI
import Combine
import WidgetKit
import AppKit

enum PackageFilterType: String, CaseIterable, Identifiable {
    case all = "All"
    case casks = "Casks"
    case formulae = "Formulae"
    case nodeNpm = "Node/NPM"
    case standalone = "Apps"
    case localBin = "Binaries"
    case outdated = "Outdated"
    
    var id: String { rawValue }
}

enum PackageSortType: String, CaseIterable, Identifiable {
    case name = "Name"
    case size = "Disk Size"
    
    var id: String { rawValue }
}

@MainActor
final class PackagesViewModel: ObservableObject {
    @Published var formulae: [PackageDisplayItem] = []
    @Published var casks: [PackageDisplayItem] = []
    @Published var nodeAndNpmItems: [PackageDisplayItem] = []
    @Published var standaloneApps: [PackageDisplayItem] = []
    @Published var localBinaries: [PackageDisplayItem] = []
    
    @Published var isLoading: Bool = false
    @Published var isUpdating: Bool = false
    @Published var outputLog: String = ""
    @Published var showLog: Bool = false
    @Published var showingImport: Bool = false
    @Published var backupData: BackupData?
    
    // Uninstall modal state
    @Published var itemToUninstall: PackageDisplayItem? = nil
    @Published var showingUninstallConfirm: Bool = false
    @Published var zapCaskPreferences: Bool = false
    
    // Filtering & Sorting
    @Published var searchText: String = ""
    @Published var selectedFilter: PackageFilterType = .all
    @Published var selectedSort: PackageSortType = .name
    
    var totalOutdatedCount: Int {
        formulae.filter { $0.hasUpdate }.count + casks.filter { $0.hasUpdate }.count
    }
    
    var allItems: [PackageDisplayItem] {
        formulae + casks + nodeAndNpmItems + standaloneApps + localBinaries
    }
    
    var displayedItems: [PackageDisplayItem] {
        var list: [PackageDisplayItem]
        switch selectedFilter {
        case .all:
            list = allItems
        case .casks:
            list = casks
        case .formulae:
            list = formulae
        case .nodeNpm:
            list = nodeAndNpmItems
        case .standalone:
            list = standaloneApps
        case .localBin:
            list = localBinaries
        case .outdated:
            list = allItems.filter { $0.hasUpdate }
        }
        
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(query) ||
                $0.description.lowercased().contains(query) ||
                $0.id.lowercased().contains(query) ||
                ($0.badgeText?.lowercased().contains(query) ?? false)
            }
        }
        
        switch selectedSort {
        case .name:
            return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            return list.sorted { $0.rawBytes > $1.rawBytes }
        }
    }
    
    func fetchPackages() async {
        self.isLoading = true
        do {
            async let infoResult = BrewQueue.shared.execute(arguments: ["info", "--json=v2", "--installed"])
            async let outdatedResult = BrewQueue.shared.execute(arguments: ["outdated", "--json=v2", "--greedy"])
            
            let (infoRes, outdatedRes) = try await (infoResult, outdatedResult)
            
            guard infoRes.exitCode == 0, let infoData = infoRes.output.data(using: .utf8) else {
                throw NSError(domain: "BrewQueue", code: infoRes.exitCode, userInfo: [NSLocalizedDescriptionKey: infoRes.error.isEmpty ? "Failed to query Homebrew packages." : infoRes.error])
            }
            
            let outdatedMap = await Task.detached { () -> (formulae: [String: String], casks: [String: String]) in
                guard let outData = outdatedRes.output.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(BrewOutdatedResponse.self, from: outData) else {
                    return ([:], [:])
                }
                var fMap = [String: String]()
                for f in decoded.formulae { fMap[f.name] = f.current_version }
                var cMap = [String: String]()
                for c in decoded.casks { cMap[c.name] = c.current_version }
                return (fMap, cMap)
            }.value
            
            let (formulaItems, caskItems, nodeNpmItems, standaloneItems, localItems, widgetData) = try await Task.detached(priority: .userInitiated) {
                let response = try JSONDecoder().decode(BrewInfoResponse.self, from: infoData)
                let graph = DependencyGraph(response: response)
                let scanner = LocalSystemScanner()
                
                // 1. Formulae Leaves
                var fItems = [PackageDisplayItem]()
                let leaves = response.formulae.filter { pkg in
                    pkg.installed.contains(where: { $0.installed_on_request == true })
                }
                for pkg in leaves {
                    var visited = Set<String>()
                    let totalBytes = graph.sizeOf(package: pkg.name, visited: &visited)
                    let newVersion = outdatedMap.formulae[pkg.name]
                    fItems.append(PackageDisplayItem(
                        id: pkg.name,
                        name: pkg.name,
                        description: pkg.desc ?? "Formula",
                        sizeString: graph.formattedSize(bytes: totalBytes),
                        rawBytes: totalBytes,
                        kind: .formula,
                        outdatedVersion: newVersion
                    ))
                }
                
                // 2. Casks
                var cItems = [PackageDisplayItem]()
                let installedCasks = response.casks.filter { $0.installed != nil }
                for cask in installedCasks {
                    let totalBytes = graph.sizeOf(cask: cask)
                    let newVersion = outdatedMap.casks[cask.token]
                    cItems.append(PackageDisplayItem(
                        id: cask.token,
                        name: cask.displayName,
                        description: cask.desc ?? cask.token,
                        sizeString: graph.formattedSize(bytes: totalBytes),
                        rawBytes: totalBytes,
                        kind: .cask,
                        outdatedVersion: newVersion
                    ))
                }
                
                // 3. NVM Node.js Versions & Global NPM Packages
                let (rawNvmNodes, rawNpmGlobals) = scanner.scanNvmAndNpm()
                var nItems = [PackageDisplayItem]()
                for node in rawNvmNodes {
                    let desc = node.isDefault
                        ? "Default NVM Node.js runtime (includes npm & corepack)"
                        : "NVM Node.js runtime (includes npm & corepack)"
                    nItems.append(PackageDisplayItem(
                        id: node.path,
                        name: "Node.js \(node.version)",
                        description: desc,
                        sizeString: graph.formattedSize(bytes: node.sizeBytes),
                        rawBytes: node.sizeBytes,
                        kind: .nvmNode,
                        filePath: node.path,
                        badgeText: node.isDefault ? "NVM Default" : "NVM Runtime"
                    ))
                }
                for npmPkg in rawNpmGlobals {
                    nItems.append(PackageDisplayItem(
                        id: npmPkg.path,
                        name: npmPkg.name,
                        description: npmPkg.description,
                        sizeString: graph.formattedSize(bytes: npmPkg.sizeBytes),
                        rawBytes: npmPkg.sizeBytes,
                        kind: .npmGlobal,
                        filePath: npmPkg.path,
                        badgeText: npmPkg.nodeLabel,
                        npmBinaryPath: npmPkg.npmBinaryPath
                    ))
                }
                
                // 4. Standalone GUI Emulators (outside Homebrew)
                let managedTokens = Set(installedCasks.map { $0.token })
                let managedNames = Set(installedCasks.map { $0.displayName })
                let rawStandalone = scanner.scanStandaloneEmulators(managedCaskTokens: managedTokens, managedCaskNames: managedNames)
                var sItems = [PackageDisplayItem]()
                for app in rawStandalone {
                    sItems.append(PackageDisplayItem(
                        id: app.bundlePath,
                        name: app.name,
                        description: app.isSystemProtected ? "macOS Built-in Terminal" : "Standalone GUI App",
                        sizeString: graph.formattedSize(bytes: app.sizeBytes),
                        rawBytes: app.sizeBytes,
                        kind: .standaloneApp,
                        isSystemProtected: app.isSystemProtected,
                        filePath: app.bundlePath
                    ))
                }
                
                // 5. Local Binaries (~/.local/bin)
                let rawLocalBinaries = scanner.scanLocalBinaries()
                var lItems = [PackageDisplayItem]()
                for bin in rawLocalBinaries {
                    let desc = bin.targetPath != nil ? "Symlink -> \(bin.targetPath!)" : "Local executable"
                    lItems.append(PackageDisplayItem(
                        id: bin.path,
                        name: bin.name,
                        description: desc,
                        sizeString: graph.formattedSize(bytes: bin.sizeBytes),
                        rawBytes: bin.sizeBytes,
                        kind: .localBinary,
                        filePath: bin.path
                    ))
                }
                
                // Total physical disk computation (avoiding double counting npm globals inside NVM nodes)
                var totalBytes = graph.totalPhysicalBytes(
                    leaves: leaves.map { $0.name },
                    casks: installedCasks
                )
                for node in rawNvmNodes { totalBytes += Int64(node.sizeBytes) }
                for npmPkg in rawNpmGlobals where !npmPkg.isInsideNvm { totalBytes += Int64(npmPkg.sizeBytes) }
                for app in rawStandalone { totalBytes += Int64(app.sizeBytes) }
                for bin in rawLocalBinaries { totalBytes += Int64(bin.sizeBytes) }
                
                let wData = WidgetData(
                    appsCount: cItems.count + sItems.count,
                    packagesCount: fItems.count + lItems.count + nItems.count,
                    totalBytes: totalBytes,
                    formattedDiskSpace: graph.formattedSize(bytes: Int(totalBytes)),
                    lastUpdated: Date()
                )
                
                return (fItems, cItems, nItems, sItems, lItems, wData)
            }.value
            
            self.formulae = formulaItems
            self.casks = caskItems
            self.nodeAndNpmItems = nodeNpmItems
            self.standaloneApps = standaloneItems
            self.localBinaries = localItems
            widgetData.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            self.outputLog = "Error fetching packages: \(error.localizedDescription)"
            self.showLog = true
        }
        self.isLoading = false
        self.isUpdating = false
    }
    
    func upgradeItem(item: PackageDisplayItem) {
        self.isUpdating = true
        self.showLog = true
        self.outputLog = "Upgrading \(item.name)...\n"
        Task {
            do {
                var args = ["upgrade"]
                if item.isCask {
                    args.append("--cask")
                }
                args.append(item.id)
                let stream = await BrewQueue.shared.stream(arguments: args)
                for try await line in stream {
                    self.outputLog += line
                }
                self.outputLog += "\nUpgrade of \(item.name) completed.\n"
                await fetchPackages()
            } catch {
                self.outputLog += "\nError: \(error.localizedDescription)\n"
            }
            self.isUpdating = false
        }
    }
    
    func updatePackages() {
        self.isUpdating = true
        self.showLog = true
        self.outputLog = "Starting brew update & upgrade...\n"
        Task {
            do {
                let streamUpdate = await BrewQueue.shared.stream(arguments: ["update"])
                for try await line in streamUpdate {
                    self.outputLog += line
                }
                self.outputLog += "\nUpdating packages & casks (brew upgrade)...\n"
                let streamUpgrade = await BrewQueue.shared.stream(arguments: ["upgrade"])
                for try await line in streamUpgrade {
                    self.outputLog += line
                }
                self.outputLog += "\nUpdate finished successfully.\n"
                await fetchPackages()
            } catch {
                self.outputLog += "\nError: \(error.localizedDescription)\n"
            }
            self.isUpdating = false
        }
    }
    
    func uninstall(item: PackageDisplayItem, zap: Bool = false) {
        self.isUpdating = true
        self.showLog = true
        self.outputLog = "Uninstalling \(item.name)...\n"
        Task {
            do {
                switch item.kind {
                case .cask:
                    var args = ["uninstall", "--cask"]
                    if zap { args.append("--zap") }
                    args.append(item.id)
                    let stream = await BrewQueue.shared.stream(arguments: args)
                    for try await line in stream {
                        self.outputLog += line
                    }
                case .formula:
                    let stream = await BrewQueue.shared.stream(arguments: ["uninstall", item.id])
                    for try await line in stream {
                        self.outputLog += line
                    }
                    self.outputLog += "\nCleaning up orphaned dependencies (brew autoremove)...\n"
                    let streamAutoremove = await BrewQueue.shared.stream(arguments: ["autoremove"])
                    for try await line in streamAutoremove {
                        self.outputLog += line
                    }
                case .nvmNode:
                    if let path = item.filePath {
                        self.outputLog += "Removing NVM Node runtime at \(path)...\n"
                        try FileManager.default.removeItem(atPath: path)
                        self.outputLog += "Removed \(item.name) successfully.\n"
                    }
                case .npmGlobal:
                    if let npmBin = item.npmBinaryPath, FileManager.default.fileExists(atPath: npmBin) {
                        let nodeBinDir = URL(fileURLWithPath: npmBin).deletingLastPathComponent().path
                        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
                        let customEnv = ["PATH": "\(nodeBinDir):\(existingPath)"]
                        self.outputLog += "Running \(npmBin) uninstall -g \(item.name)...\n"
                        let stream = ProcessRunner().streamProcess(
                            executableURL: URL(fileURLWithPath: npmBin),
                            arguments: ["uninstall", "-g", item.name],
                            environment: customEnv
                        )
                        for try await line in stream {
                            self.outputLog += line
                        }
                    } else if let path = item.filePath {
                        self.outputLog += "Removing global npm package directory at \(path)...\n"
                        try FileManager.default.removeItem(atPath: path)
                    }
                case .standaloneApp:
                    if let path = item.filePath {
                        let url = URL(fileURLWithPath: path)
                        self.outputLog += "Moving \(path) to Trash...\n"
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        self.outputLog += "Moved to Trash successfully.\n"
                    }
                case .localBinary:
                    if let path = item.filePath {
                        self.outputLog += "Deleting \(path)...\n"
                        try FileManager.default.removeItem(atPath: path)
                        self.outputLog += "Deleted successfully.\n"
                    }
                }
                
                self.outputLog += "\nUninstallation finished successfully.\n"
                await fetchPackages()
            } catch {
                self.outputLog += "\nError during uninstallation: \(error.localizedDescription)\n"
            }
            self.isUpdating = false
        }
    }
    
    func importPackages(toInstallFormulae: [String], toInstallCasks: [String]) {
        self.isUpdating = true
        self.showLog = true
        self.outputLog = "Starting import installation...\n"
        Task {
            do {
                if !toInstallCasks.isEmpty {
                    self.outputLog += "Installing casks: \(toInstallCasks.joined(separator: ", "))...\n"
                    let streamCasks = await BrewQueue.shared.stream(arguments: ["install", "--cask"] + toInstallCasks)
                    for try await line in streamCasks {
                        self.outputLog += line
                    }
                }
                if !toInstallFormulae.isEmpty {
                    self.outputLog += "\nInstalling formulae: \(toInstallFormulae.joined(separator: ", "))...\n"
                    let streamFormulae = await BrewQueue.shared.stream(arguments: ["install"] + toInstallFormulae)
                    for try await line in streamFormulae {
                        self.outputLog += line
                    }
                }
                self.outputLog += "\nImport installation completed.\n"
                await fetchPackages()
            } catch {
                self.outputLog += "\nError during import installation: \(error.localizedDescription)\n"
            }
            self.isUpdating = false
        }
    }
    
    func exportConfig(asBrewfile: Bool = false) {
        let panel = NSSavePanel()
        if asBrewfile {
            panel.nameFieldStringValue = "Brewfile"
        } else {
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "TerminalManager_Backup.json"
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            let formulaNames = self.formulae.map { $0.id }
            let caskTokens = self.casks.map { $0.id }
            do {
                if asBrewfile {
                    try BackupManager.exportBrewfile(formulae: formulaNames, casks: caskTokens, to: url)
                } else {
                    try BackupManager.export(formulae: formulaNames, casks: caskTokens, to: url)
                }
            } catch {
                self.outputLog = "Export error: \(error.localizedDescription)"
                self.showLog = true
            }
        }
    }
    
    func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try BackupManager.load(from: url)
                self.backupData = data
                self.showingImport = true
            } catch {
                self.outputLog = "Import error: \(error.localizedDescription)"
                self.showLog = true
            }
        }
    }
}

struct PackagesView: View {
    @StateObject private var viewModel = PackagesViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Terminal Manager")
                        .font(.headline)
                    Text("\(viewModel.casks.count) Casks · \(viewModel.formulae.count) Formulae · \(viewModel.nodeAndNpmItems.count) Node/NPM · \(viewModel.standaloneApps.count) Apps · \(viewModel.localBinaries.count) Binaries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Menu {
                    Button("Export JSON Backup...") {
                        viewModel.exportConfig(asBrewfile: false)
                    }
                    Button("Export Brewfile...") {
                        viewModel.exportConfig(asBrewfile: true)
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.isUpdating)
                
                Button {
                    viewModel.importConfig()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.isUpdating)
                
                Button {
                    viewModel.updatePackages()
                } label: {
                    Label(viewModel.isUpdating ? "Updating..." : "Update All", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(viewModel.isUpdating)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            Divider()
            
            // Search, Filter & Sort Controls
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search packages, Node/NPM, casks or binaries...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                
                Picker("", selection: $viewModel.selectedFilter) {
                    ForEach(PackageFilterType.allCases) { filter in
                        if filter == .outdated {
                            Text("Outdated (\(viewModel.totalOutdatedCount))").tag(filter)
                        } else {
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 440)
                
                Picker("Sort", selection: $viewModel.selectedSort) {
                    ForEach(PackageSortType.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .frame(width: 120)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Live Output Console
            if viewModel.showLog {
                VStack(spacing: 4) {
                    HStack {
                        Text("Process Output Console")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.secondary)
                        Spacer()
                        if !viewModel.isUpdating {
                            Button("Close Console") {
                                viewModel.showLog = false
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    
                    ScrollView {
                        Text(viewModel.outputLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 6)
                    }
                    .frame(maxHeight: 140)
                }
                .background(Color(NSColor.textBackgroundColor))
                Divider()
            }
            
            // Package List
            if viewModel.isLoading {
                Spacer()
                ProgressView("Auditing system packages, NVM/NPM, and emulators...")
                Spacer()
            } else if viewModel.displayedItems.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No items found.")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.displayedItems) { item in
                        packageRow(item: item)
                    }
                }
            }
        }
        .task {
            await viewModel.fetchPackages()
        }
        .sheet(isPresented: $viewModel.showingImport) {
            if let backup = viewModel.backupData {
                ImportChecklistView(
                    backup: backup,
                    installedFormulae: Set(viewModel.formulae.map { $0.id }),
                    installedCasks: Set(viewModel.casks.map { $0.id }),
                    isPresented: $viewModel.showingImport,
                    onInstall: { fList, cList in
                        viewModel.importPackages(toInstallFormulae: fList, toInstallCasks: cList)
                    }
                )
            }
        }
        .alert("Uninstall \(viewModel.itemToUninstall?.name ?? "")?", isPresented: $viewModel.showingUninstallConfirm) {
            Button("Cancel", role: .cancel) {
                viewModel.itemToUninstall = nil
                viewModel.zapCaskPreferences = false
            }
            Button("Uninstall", role: .destructive) {
                if let item = viewModel.itemToUninstall {
                    let zap = viewModel.zapCaskPreferences
                    viewModel.uninstall(item: item, zap: zap)
                    viewModel.itemToUninstall = nil
                    viewModel.zapCaskPreferences = false
                }
            }
        } message: {
            if let item = viewModel.itemToUninstall {
                if item.isCask {
                    Text("Are you sure you want to uninstall '\(item.name)'? This will free approximately \(item.sizeString) of disk space.")
                } else if item.isNvmNode {
                    Text("Are you sure you want to remove NVM Node runtime '\(item.name)' and all global npm packages installed under it (\(item.sizeString))?")
                } else if item.isNpmGlobal {
                    Text("Are you sure you want to uninstall global npm package '\(item.name)' (\(item.badgeText ?? "npm"))?")
                } else if item.isStandaloneApp {
                    Text("Are you sure you want to move '\(item.name)' to Trash? This will free approximately \(item.sizeString).")
                } else if item.isLocalBinary {
                    Text("Are you sure you want to delete binary '\(item.name)' from ~/.local/bin?")
                } else {
                    Text("Are you sure you want to uninstall '\(item.name)'? Unused dependencies will also be removed.")
                }
            }
        }
    }
    
    @ViewBuilder
    private func packageRow(item: PackageDisplayItem) -> some View {
        HStack {
            Image(systemName: iconName(for: item.kind))
                .foregroundColor(iconColor(for: item.kind))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline)
                        .bold()
                    
                    if let newVersion = item.outdatedVersion {
                        Text("Update: \(newVersion)")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                    
                    if let badge = item.badgeText {
                        Text(badge)
                            .font(.caption2)
                            .foregroundColor(item.isNvmNode ? .teal : .pink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill((item.isNvmNode ? Color.teal : Color.pink).opacity(0.15)))
                    }
                    
                    if item.isSystemProtected {
                        Text("System")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    } else if item.isStandaloneApp {
                        Text("Standalone")
                            .font(.caption2)
                            .foregroundColor(.purple)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                    } else if item.isLocalBinary {
                        Text("~/.local/bin")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                    }
                }
                
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(item.sizeString)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .padding(.trailing, 6)
            
            if item.hasUpdate {
                Button("Update") {
                    viewModel.upgradeItem(item: item)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isUpdating)
            }
            
            if !item.isSystemProtected {
                Button(role: .destructive) {
                    viewModel.itemToUninstall = item
                    viewModel.showingUninstallConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Uninstall \(item.name)")
                .disabled(viewModel.isUpdating)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
                    .help("Protected by macOS system")
            }
        }
        .padding(.vertical, 3)
    }
    
    private func iconName(for kind: PackageKind) -> String {
        switch kind {
        case .cask: return "macwindow"
        case .formula: return "terminal"
        case .nvmNode: return "shippingbox.fill"
        case .npmGlobal: return "cube.box.fill"
        case .standaloneApp: return "app.dashed"
        case .localBinary: return "chevron.left.forwardslash.chevron.right"
        }
    }
    
    private func iconColor(for kind: PackageKind) -> Color {
        switch kind {
        case .cask: return .accentColor
        case .formula: return .green
        case .nvmNode: return .teal
        case .npmGlobal: return .pink
        case .standaloneApp: return .purple
        case .localBinary: return .blue
        }
    }
}
