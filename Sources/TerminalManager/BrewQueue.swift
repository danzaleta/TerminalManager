import Foundation

public actor BrewQueue {
    public static let shared = BrewQueue()
    private let runner = ProcessRunner()
    private var brewURL: URL? { BrewLocator.findBrew() }
    
    private let standardEnv = [
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "NONINTERACTIVE": "1"
    ]
    
    public init() {}
    
    public func execute(arguments: [String]) async throws -> ProcessResult {
        guard let brew = brewURL else {
            throw NSError(domain: "BrewQueue", code: 1, userInfo: [NSLocalizedDescriptionKey: "Homebrew not found"])
        }
        return try await runner.runProcess(
            executableURL: brew,
            arguments: arguments,
            environment: standardEnv
        )
    }
    
    public func stream(arguments: [String]) -> AsyncThrowingStream<String, Error> {
        guard let brew = brewURL else {
            return AsyncThrowingStream { $0.finish(throwing: NSError(domain: "BrewQueue", code: 1, userInfo: [NSLocalizedDescriptionKey: "Homebrew not found"])) }
        }
        return runner.streamProcess(
            executableURL: brew,
            arguments: arguments,
            environment: standardEnv
        )
    }
}
