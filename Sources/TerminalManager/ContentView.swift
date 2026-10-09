import SwiftUI

struct SettingsView: View {
    @State private var outputText: String = "Fetching brew list..."
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("TerminalManager")
                .font(.title)
                .padding(.bottom)
            
            ScrollView {
                Text(outputText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack {
                Button("Run brew update") {
                    outputText = "Updating..."
                    Task {
                        do {
                            let stream = BrewQueue.shared.stream(arguments: ["update"])
                            var newText = ""
                            for try await line in stream {
                                newText += line
                                await MainActor.run {
                                    self.outputText = newText
                                }
                            }
                        } catch {
                            await MainActor.run {
                                self.outputText += "\nError: \(error)"
                            }
                        }
                    }
                }
                Spacer()
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .task {
            do {
                let result = try await BrewQueue.shared.execute(arguments: ["list", "--formula"])
                outputText = "Formulae:\n" + result.output
            } catch {
                outputText = "Error: \(error.localizedDescription)"
            }
        }
    }
}
