import SwiftUI

class ImportChecklistViewModel: ObservableObject {
    @Published var selectedFormulae: Set<String>
    
    init(backup: BackupData) {
        self.selectedFormulae = Set(backup.formulae)
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
            Text("Confirm Import").font(.headline).padding()
            
            List(backup.formulae, id: \.self) { pkg in
                Toggle(pkg, isOn: Binding(
                    get: { viewModel.selectedFormulae.contains(pkg) },
                    set: { isOn in
                        if isOn { viewModel.selectedFormulae.insert(pkg) }
                        else { viewModel.selectedFormulae.remove(pkg) }
                    }
                ))
            }
            
            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Install Selected") {
                    let toInstall = Array(viewModel.selectedFormulae)
                    Task {
                        _ = try? await BrewQueue.shared.execute(arguments: ["install"] + toInstall)
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }
}
