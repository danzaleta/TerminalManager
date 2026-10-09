import SwiftUI

class ImportChecklistViewModel: ObservableObject {
    @Published var selectedFormulae: Set<String>
    @Published var selectedCasks: Set<String>
    
    init(backup: BackupData) {
        self.selectedFormulae = Set(backup.formulae)
        self.selectedCasks = Set(backup.casks)
    }
}

struct ImportChecklistView: View {
    let backup: BackupData
    @Binding var isPresented: Bool
    @StateObject private var viewModel: ImportChecklistViewModel
    
    init(backup: BackupData, isPresented: Binding<Bool>) {
        self.backup = backup
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: ImportChecklistViewModel(backup: backup))
    }
    
    var body: some View {
        VStack {
            Text("Confirm Import").font(.headline).padding(.top)
            
            List {
                if !backup.casks.isEmpty {
                    Section("Apps (Casks)") {
                        ForEach(backup.casks, id: \.self) { cask in
                            Toggle(cask, isOn: Binding(
                                get: { viewModel.selectedCasks.contains(cask) },
                                set: { isOn in
                                    if isOn { viewModel.selectedCasks.insert(cask) }
                                    else { viewModel.selectedCasks.remove(cask) }
                                }
                            ))
                        }
                    }
                }
                
                if !backup.formulae.isEmpty {
                    Section("Packages (Formulae)") {
                        ForEach(backup.formulae, id: \.self) { pkg in
                            Toggle(pkg, isOn: Binding(
                                get: { viewModel.selectedFormulae.contains(pkg) },
                                set: { isOn in
                                    if isOn { viewModel.selectedFormulae.insert(pkg) }
                                    else { viewModel.selectedFormulae.remove(pkg) }
                                }
                            ))
                        }
                    }
                }
            }
            
            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Install Selected") {
                    let toInstallFormulae = Array(viewModel.selectedFormulae)
                    let toInstallCasks = Array(viewModel.selectedCasks)
                    Task {
                        if !toInstallCasks.isEmpty {
                            _ = try? await BrewQueue.shared.execute(arguments: ["install", "--cask"] + toInstallCasks)
                        }
                        if !toInstallFormulae.isEmpty {
                            _ = try? await BrewQueue.shared.execute(arguments: ["install"] + toInstallFormulae)
                        }
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }
}
