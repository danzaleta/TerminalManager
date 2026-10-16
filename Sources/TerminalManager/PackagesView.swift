import Foundation
import SwiftUI
import Combine
import WidgetKit

enum PackageFilterType: String, CaseIterable, Identifiable {
    case all = "All"
    case casks = "GUI Casks"
    case formulae = "Formulae"
    
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
    @Published var isLoading: Bool = false
    @Published var isUpdating: Bool = false
    @Published var outputLog: String = ""
    @Published var showLog: Bool = false
    @Published var showingImport: Bool = false
    @Published var backupData: BackupData?
    @Published var itemToUninstall: PackageDisplayItem? = nil
    @Published var showingUninstallConfirm: Bool = false
    
    // Filtering & Sorting
    @Published var searchText: String = ""
    @Published var selectedFilter: PackageFilterType = .all
    @Published var selectedSort: PackageSortType = .name
    
    var filteredCasks: [PackageDisplayItem] {
        guard selectedFilter == .all || selectedFilter == .casks else { return [] }
        var list = casks
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let query = searchText.lowercased()
            list = list.filter { $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query) || $0.id.lowercased().contains(query) }
        }
        switch selectedSort {
        case .name:
            return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            return list.sorted { $0.rawBytes > $1.rawBytes }
        }
    }
    
    var filteredFormulae: [PackageDisplayItem] {
        guard selectedFilter == .all || selectedFilter == .formulae else { return [] }
        var list = formulae
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let query = searchText.lowercased()
            list = list.filter { $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query) || $0.id.lowercased().contains(query) }
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
            let result = try await BrewQueue.shared.execute(arguments: ["info", "--json=v2", "--installed"])
            guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
                throw NSError(domain: "BrewQueue", code: result.exitCode, userInfo: [NSLocalizedDescriptionKey: result.error.isEmpty ? "Failed to query Homebrew packages." : result.error])
            }
            
            // Heavy parsing and disk measurement on background thread
            let (formulaItems, caskItems, widgetData) = try await Task.detached(priority: .userInitiated) {
                let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
                let graph = DependencyGraph(response: response)
                
                // Formulae leaves (installed on request)
                var fItems = [PackageDisplayItem]()
                let leaves = response.formulae.filter { pkg in
                    pkg.installed.contains(where: { $0.installed_on_request == true })
                }
                
                for pkg in leaves {
                    var visited = Set<String>()
                    let totalBytes = graph.sizeOf(package: pkg.name, visited: &visited)
                    fItems.append(PackageDisplayItem(
                        id: pkg.name,
                        name: pkg.name,
                        description: pkg.desc ?? "No description",
                        sizeString: graph.formattedSize(bytes: totalBytes),
                        rawBytes: totalBytes,
                        isCask: false
                    ))
                }
                
                // Casks
                var cItems = [PackageDisplayItem]()
                let installedCasks = response.casks.filter { $0.installed != nil }
                for cask in installedCasks {
                    let totalBytes = graph.sizeOf(cask: cask)
                    cItems.append(PackageDisplayItem(
                        id: cask.token,
                        name: cask.displayName,
                        description: cask.desc ?? cask.token,
                        sizeString: graph.formattedSize(bytes: totalBytes),
                        rawBytes: totalBytes,
                        isCask: true
                    ))
                }
                
                // True aggregate physical size without duplicate counting
                let totalAllBytes = graph.totalPhysicalBytes(
                    leaves: leaves.map { $0.name },
                    casks: installedCasks
                )
                
                let wData = WidgetData(
                    appsCount: cItems.count,
                    packagesCount: fItems.count,
                    totalBytes: totalAllBytes,
                    formattedDiskSpace: graph.formattedSize(bytes: Int(totalAllBytes)),
                    lastUpdated: Date()
                )
                
                return (fItems, cItems, wData)
            }.value
            
            self.formulae = formulaItems
            self.casks = caskItems
            widgetData.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            self.outputLog = "Error fetching packages: \(error.localizedDescription)"
            self.showLog = true
        }
        self.isLoading = false
        self.isUpdating = false
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
    
    func uninstall(item: PackageDisplayItem) {
        self.isUpdating = true
        self.showLog = true
        self.outputLog = "Uninstalling \(item.name) (\(item.id))...\n"
        Task {
            do {
                var args = ["uninstall"]
                if item.isCask {
                    args.append("--cask")
                }
                args.append(item.id)
                
                let stream = await BrewQueue.shared.stream(arguments: args)
                for try await line in stream {
                    self.outputLog += line
                }
                
                if !item.isCask {
                    self.outputLog += "\nCleaning up orphaned dependencies (brew autoremove)...\n"
                    let streamAutoremove = await BrewQueue.shared.stream(arguments: ["autoremove"])
                    for try await line in streamAutoremove {
                        self.outputLog += line
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
    
    func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "TerminalManager_Backup.json"
        
        if panel.runModal() == .OK, let url = panel.url {
            let formulaNames = self.formulae.map { $0.id }
            let caskTokens = self.casks.map { $0.id }
            do {
                try BackupManager.export(formulae: formulaNames, casks: caskTokens, to: url)
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
            // Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Terminal Manager")
                        .font(.headline)
                    Text("\(viewModel.casks.count) GUI Casks · \(viewModel.formulae.count) Formulae Leaves")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    viewModel.importConfig()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.isUpdating)
                
                Button {
                    viewModel.exportConfig()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
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
                    TextField("Search packages or apps...", text: $viewModel.searchText)
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
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                
                Picker("Sort", selection: $viewModel.selectedSort) {
                    ForEach(PackageSortType.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .frame(width: 130)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Process Log Console
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
            
            // Main Package List
            if viewModel.isLoading {
                Spacer()
                ProgressView("Auditing packages and disk sizes...")
                Spacer()
            } else if viewModel.filteredCasks.isEmpty && viewModel.filteredFormulae.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No packages match your criteria.")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    if !viewModel.filteredCasks.isEmpty {
                        Section("GUI Terminal Apps & Casks (\(viewModel.filteredCasks.count))") {
                            ForEach(viewModel.filteredCasks) { item in
                                packageRow(item: item)
                            }
                        }
                    }
                    
                    if !viewModel.filteredFormulae.isEmpty {
                        Section("CLI Packages & Dependencies (\(viewModel.filteredFormulae.count))") {
                            ForEach(viewModel.filteredFormulae) { item in
                                packageRow(item: item)
                            }
                        }
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
            }
            Button("Uninstall", role: .destructive) {
                if let item = viewModel.itemToUninstall {
                    viewModel.uninstall(item: item)
                    viewModel.itemToUninstall = nil
                }
            }
        } message: {
            if let item = viewModel.itemToUninstall {
                Text("Are you sure you want to uninstall '\(item.name)'? This will free approximately \(item.sizeString) of disk space.")
            }
        }
    }
    
    @ViewBuilder
    private func packageRow(item: PackageDisplayItem) -> some View {
        HStack {
            Image(systemName: item.isCask ? "macwindow" : "terminal")
                .foregroundColor(.accentColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .bold()
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(item.sizeString)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .padding(.trailing, 8)
            
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
        }
        .padding(.vertical, 3)
    }
}
