import Foundation
import SwiftUI
import Combine

@MainActor
class PackagesViewModel: ObservableObject {
    @Published var formulae: [(package: BrewPackage, totalSizeStr: String)] = []
    @Published var casks: [(cask: BrewCask, totalSizeStr: String)] = []
    @Published var isLoading: Bool = false
    @Published var isUpdating: Bool = false
    @Published var outputLog: String = ""
    @Published var showingImport = false
    @Published var backupData: BackupData?
    
    func fetchPackages() async {
        self.isLoading = true
        do {
            let result = try await BrewQueue.shared.execute(arguments: ["info", "--json=v2", "--installed"])
            if let data = result.output.data(using: .utf8) {
                let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
                let graph = DependencyGraph(response: response)
                
                // Formulae
                var formulaItems = [(package: BrewPackage, totalSizeStr: String)]()
                for pkg in response.formulae where pkg.installed.contains(where: { $0.installed_on_request == true }) {
                    var visited = Set<String>()
                    let totalBytes = graph.sizeOf(package: pkg.name, visited: &visited)
                    formulaItems.append((package: pkg, totalSizeStr: graph.formattedSize(bytes: totalBytes)))
                }
                self.formulae = formulaItems.sorted { a, b in a.package.name < b.package.name }
                
                // Casks
                var caskItems = [(cask: BrewCask, totalSizeStr: String)]()
                for cask in response.casks where cask.installed != nil {
                    let totalBytes = graph.sizeOf(cask: cask)
                    caskItems.append((cask: cask, totalSizeStr: graph.formattedSize(bytes: totalBytes)))
                }
                self.casks = caskItems.sorted { a, b in a.cask.displayName < b.cask.displayName }
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
    
    func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "TerminalManager_Backup.json"
        
        if panel.runModal() == .OK, let url = panel.url {
            let formulaNames = self.formulae.map { $0.package.name }
            let caskTokens = self.casks.map { $0.cask.token }
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
            
            if viewModel.isUpdating {
                ScrollView {
                    Text(viewModel.outputLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 130)
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
                            ForEach(viewModel.casks, id: \.cask.id) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.cask.displayName).font(.subheadline).bold()
                                        Text(item.cask.desc ?? item.cask.token)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(item.totalSizeStr)
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    
                    if !viewModel.formulae.isEmpty {
                        Section("CLI Packages & Dependencies (Formulae)") {
                            ForEach(viewModel.formulae, id: \.package.id) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.package.name).font(.subheadline).bold()
                                        Text(item.package.desc ?? "No description")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(item.totalSizeStr)
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
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
    }
}
