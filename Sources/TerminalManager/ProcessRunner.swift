import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int
    public let output: String
    public let error: String
}

public struct ProcessRunner {
    public init() {}
    
    public func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        var currentEnv = ProcessInfo.processInfo.environment
        if let env = environment {
            currentEnv.merge(env) { (_, new) in new }
        }
        let additionalPath = "/opt/homebrew/bin:/usr/local/bin"
        if let existingPath = currentEnv["PATH"] {
            currentEnv["PATH"] = "\(additionalPath):\(existingPath)"
        } else {
            currentEnv["PATH"] = additionalPath
        }
        process.environment = currentEnv
        if let cwd = workingDirectory {
            process.currentDirectoryURL = cwd
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = try? outputPipe.fileHandleForReading.readToEnd()
        let errorData = try? errorPipe.fileHandleForReading.readToEnd()
        
        let outputStr = outputData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let errorStr = errorData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        
        return ProcessResult(exitCode: Int(process.terminationStatus), output: outputStr, error: errorStr)
    }
    
    public func streamProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            var currentEnv = ProcessInfo.processInfo.environment
            if let env = environment {
                currentEnv.merge(env) { (_, new) in new }
            }
            let additionalPath = "/opt/homebrew/bin:/usr/local/bin"
            if let existingPath = currentEnv["PATH"] {
                currentEnv["PATH"] = "\(additionalPath):\(existingPath)"
            } else {
                currentEnv["PATH"] = additionalPath
            }
            process.environment = currentEnv
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                    continuation.yield(str)
                }
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                    continuation.yield(str)
                }
            }
            
            process.terminationHandler = { p in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: NSError(domain: "ProcessRunner", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Process exited with code \(p.terminationStatus)"]))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
