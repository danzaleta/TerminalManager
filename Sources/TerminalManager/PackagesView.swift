import Foundation
import SwiftUI
import Combine

@MainActor
class PackagesViewModel: ObservableObject {
    @Published var formulae: [(package: BrewPackage, totalSizeStr: String)] = []
    @Published var isUpdating: Bool = false
    @Published var outputLog: String = ""
    @Published var showingImport = false
    @Published var backupData: BackupData?
    
    func fetchPackages() async {
        do {
            let result = try await BrewQueue.shared.execute(arguments: ["info", "--json=v2", "--installed"])
            if let data = result.output.data(using: .utf8) {
                let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
                let graph = DependencyGraph(response: response)
                
                var items = [(package: BrewPackage, totalSizeStr: String)]()
                for pkg in response.formulae where pkg.installed.contains(where: { $0.installed_on_request == true }) {
                    var visited = Set<String>()
                    let totalBytes = graph.sizeOf(package: pkg.name, visited: &visited)
                    items.append((package: pkg, totalSizeStr: graph.formattedSize(bytes: totalBytes)))
                }
                
                self.formulae = items.sorted { a, b in a.package.name < b.package.name }
            }
        } catch {
            self.outputLog = "Error parsing: \(error)"
            self.isUpdating = true // Hack to show the error view
            print("Error parsing: \(error)")
        }
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
                self.outputLog += "\nUpdating packages...\n"
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
            let names = self.formulae.map { $0.package.name }
            do {
                try BackupManager.export(formulae: names, casks: [], to: url)
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
        VStack {
            HStack {
                Text("Installed Packages")
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
            
            if viewModel.isUpdating {
                ScrollView {
                    Text(viewModel.outputLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 150)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            List(viewModel.formulae, id: \.package.id) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.package.name).font(.subheadline).bold()
                        Text(item.package.desc ?? "No description").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(item.totalSizeStr).font(.caption.monospacedDigit())
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
