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
        currentEnv["NONINTERACTIVE"] = "1"
        currentEnv["CI"] = "1"
        currentEnv["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        currentEnv["HOMEBREW_NO_ENV_HINTS"] = "1"
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
        process.standardInput = FileHandle.nullDevice
        if let cwd = workingDirectory {
            process.currentDirectoryURL = cwd
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        let outputTask = Task.detached {
            outputHandle.readDataToEndOfFile()
        }
        let errorTask = Task.detached {
            errorHandle.readDataToEndOfFile()
        }
        
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                continuation.resume()
            }
        }
        
        let outputData = await outputTask.value
        let errorData = await errorTask.value
        
        let outputStr = String(data: outputData, encoding: .utf8) ?? ""
        let errorStr = String(data: errorData, encoding: .utf8) ?? ""
        
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
            currentEnv["NONINTERACTIVE"] = "1"
            currentEnv["CI"] = "1"
            currentEnv["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            currentEnv["HOMEBREW_NO_ENV_HINTS"] = "1"
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
            process.standardInput = FileHandle.nullDevice
            
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
            
            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
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
