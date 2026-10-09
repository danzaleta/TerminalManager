import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var outputText: String = "Fetching brew list..."
    
    func fetchList() async {
        do {
            let result = try await BrewQueue.shared.execute(arguments: ["list", "--formula"])
            self.outputText = "Formulae:\n" + result.output
        } catch {
            self.outputText = "Error: \(error.localizedDescription)"
        }
    }
    
    func runUpdate() {
        self.outputText = "Updating..."
        Task {
            do {
                let stream = await BrewQueue.shared.stream(arguments: ["update"])
                var newText = ""
                for try await line in stream {
                    newText += line
                    self.outputText = newText
                }
            } catch {
                self.outputText += "\nError: \(error)"
            }
        }
    }
}

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("TerminalManager")
                .font(.title)
                .padding(.bottom)
            
            ScrollView {
                Text(viewModel.outputText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack {
                Button("Run brew update") {
                    viewModel.runUpdate()
                }
                Spacer()
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .task {
            await viewModel.fetchList()
        }
    }
}
