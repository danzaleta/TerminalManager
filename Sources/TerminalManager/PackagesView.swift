import Foundation
import SwiftUI
import Combine
import WidgetKit

@MainActor
class PackagesViewModel: ObservableObject {
    @Published var formulae: [PackageDisplayItem] = []
    @Published var casks: [PackageDisplayItem] = []
    @Published var isLoading: Bool = false
    @Published var isUpdating: Bool = false
    @Published var outputLog: String = ""
    @Published var showLog: Bool = false
    @Published var showingImport = false
    @Published var backupData: BackupData?
    @Published var itemToUninstall: PackageDisplayItem? = nil
    @Published var showingUninstallConfirm = false
    
    func fetchPackages() async {
        self.isLoading = true
        do {
            let result = try await BrewQueue.shared.execute(arguments: ["info", "--json=v2", "--installed"])
            if let data = result.output.data(using: .utf8) {
                let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
                let graph = DependencyGraph(response: response)
                
                // Formulae
                var formulaItems = [PackageDisplayItem]()
                for pkg in response.formulae where pkg.installed.contains(where: { $0.installed_on_request == true }) {
                    var visited = Set<String>()
                    let totalBytes = graph.sizeOf(package: pkg.name, visited: &visited)
                    formulaItems.append(PackageDisplayItem(
                        id: pkg.name,
                        name: pkg.name,
                        description: pkg.desc ?? "No description",
                        sizeString: graph.formattedSize(bytes: totalBytes),
                        isCask: false
                    ))
                }
                self.formulae = formulaItems.sorted { $0.name < $1.name }
                
                // Casks
                var caskItems = [PackageDisplayItem]()
                for cask in response.casks where cask.installed != nil {
                    let totalBytes = graph.sizeOf(cask: cask)
                    caskItems.append(PackageDisplayItem(
                        id: cask.token,
                        name: cask.displayName,
                        description: cask.desc ?? cask.token,
                        sizeString: graph.formattedSize(bytes: totalBytes),
                        isCask: true
                    ))
                }
                self.casks = caskItems.sorted { $0.name < $1.name }
                
                // Save metrics for Desktop Widget
                var totalAllBytes: Int64 = 0
                for pkg in response.formulae where pkg.installed.contains(where: { $0.installed_on_request == true }) {
                    var v = Set<String>()
                    totalAllBytes += Int64(graph.sizeOf(package: pkg.name, visited: &v))
                }
                for cask in response.casks where cask.installed != nil {
                    totalAllBytes += Int64(graph.sizeOf(cask: cask))
                }
                let widgetData = WidgetData(
                    appsCount: self.casks.count,
                    packagesCount: self.formulae.count,
                    totalBytes: totalAllBytes,
                    formattedDiskSpace: graph.formattedSize(bytes: Int(totalAllBytes)),
                    lastUpdated: Date()
                )
                widgetData.save()
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            self.outputLog = "Error fetching packages: \(error)"
            self.isUpdating = true
            print("Error: \(error)")
        }
        self.isLoading = false
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
                self.outputLog += "\nUpdating packages & casks...\n"
                let streamUpgrade = await BrewQueue.shared.stream(arguments: ["upgrade"])
                for try await line in streamUpgrade {
                    self.outputLog += line
                }
                await fetchPackages()
            } catch {
                self.outputLog += "\nError: \(error)"
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
                print("Export error: \(error)")
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
                print("Import error: \(error)")
            }
        }
    }
}

struct PackagesView: View {
    @StateObject private var viewModel = PackagesViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Installed Applications & Packages")
                    .font(.headline)
                Spacer()
                Button("Import") {
                    viewModel.importConfig()
                }
                Button("Export") {
                    viewModel.exportConfig()
                }
                Button(viewModel.isUpdating ? "Updating..." : "Update All") {
                    viewModel.updatePackages()
                }
                .disabled(viewModel.isUpdating)
            }
            .padding()
            
            Divider()
            
            if viewModel.showLog {
                VStack(spacing: 4) {
                    HStack {
                        Text("Process Log")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.secondary)
                        Spacer()
                        if !viewModel.isUpdating {
                            Button("Close Log") {
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
            
            if viewModel.isLoading {
                Spacer()
                ProgressView("Auditing packages and sizes...")
                Spacer()
            } else if viewModel.formulae.isEmpty && viewModel.casks.isEmpty {
                Spacer()
                Text("No packages found.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    if !viewModel.casks.isEmpty {
                        Section("GUI Terminal Apps (Casks)") {
                            ForEach(viewModel.casks) { item in
                                packageRow(item: item)
                            }
                        }
                    }
                    
                    if !viewModel.formulae.isEmpty {
                        Section("CLI Packages & Dependencies (Formulae)") {
                            ForEach(viewModel.formulae) { item in
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
                ImportChecklistView(backup: backup, isPresented: $viewModel.showingImport)
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
