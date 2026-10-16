import SwiftUI

final class ImportChecklistViewModel: ObservableObject {
    @Published var selectedFormulae: Set<String>
    @Published var selectedCasks: Set<String>
    let installedFormulae: Set<String>
    let installedCasks: Set<String>
    
    init(backup: BackupData, installedFormulae: Set<String>, installedCasks: Set<String>) {
        self.installedFormulae = installedFormulae
        self.installedCasks = installedCasks
        // Default selection: only packages not already installed
        self.selectedFormulae = Set(backup.formulae).subtracting(installedFormulae)
        self.selectedCasks = Set(backup.casks).subtracting(installedCasks)
    }
    
    var totalSelectedCount: Int {
        selectedFormulae.count + selectedCasks.count
    }
}

struct ImportChecklistView: View {
    let backup: BackupData
    let installedFormulae: Set<String>
    let installedCasks: Set<String>
    @Binding var isPresented: Bool
    var onInstall: ([String], [String]) -> Void
    
    @StateObject private var viewModel: ImportChecklistViewModel
    
    init(
        backup: BackupData,
        installedFormulae: Set<String>,
        installedCasks: Set<String>,
        isPresented: Binding<Bool>,
        onInstall: @escaping ([String], [String]) -> Void
    ) {
        self.backup = backup
        self.installedFormulae = installedFormulae
        self.installedCasks = installedCasks
        self._isPresented = isPresented
        self.onInstall = onInstall
        self._viewModel = StateObject(wrappedValue: ImportChecklistViewModel(
            backup: backup,
            installedFormulae: installedFormulae,
            installedCasks: installedCasks
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Backup Checklist")
                        .font(.headline)
                    Text("Exported at \(backup.timestamp.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            
            Divider()
            
            List {
                if !backup.casks.isEmpty {
                    Section("Apps & Casks (\(backup.casks.count))") {
                        ForEach(backup.casks, id: \.self) { cask in
                            let isInstalled = viewModel.installedCasks.contains(cask)
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { viewModel.selectedCasks.contains(cask) },
                                    set: { isOn in
                                        if isOn { viewModel.selectedCasks.insert(cask) }
                                        else { viewModel.selectedCasks.remove(cask) }
                                    }
                                )) {
                                    Text(cask)
                                }
                                Spacer()
                                if isInstalled {
                                    Text("Installed")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                }
                            }
                        }
                    }
                }
                
                if !backup.formulae.isEmpty {
                    Section("CLI Packages & Formulae (\(backup.formulae.count))") {
                        ForEach(backup.formulae, id: \.self) { pkg in
                            let isInstalled = viewModel.installedFormulae.contains(pkg)
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { viewModel.selectedFormulae.contains(pkg) },
                                    set: { isOn in
                                        if isOn { viewModel.selectedFormulae.insert(pkg) }
                                        else { viewModel.selectedFormulae.remove(pkg) }
                                    }
                                )) {
                                    Text(pkg)
                                }
                                Spacer()
                                if isInstalled {
                                    Text("Installed")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                }
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                Text("\(viewModel.totalSelectedCount) item(s) selected to install")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Install Selected") {
                    let toInstallFormulae = Array(viewModel.selectedFormulae)
                    let toInstallCasks = Array(viewModel.selectedCasks)
                    isPresented = false
                    onInstall(toInstallFormulae, toInstallCasks)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.totalSelectedCount == 0)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 460)
    }
}
