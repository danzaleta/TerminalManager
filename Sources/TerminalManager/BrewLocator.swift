import Foundation

public struct BrewLocator {
    public static func findBrew() -> URL? {
        // Common paths
        let paths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
    
    public static var brewPrefix: String {
        if let env = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !env.isEmpty {
            return env
        }
        if let brew = findBrew() {
            // /opt/homebrew/bin/brew -> /opt/homebrew
            return brew.deletingLastPathComponent().deletingLastPathComponent().path
        }
        return "/opt/homebrew"
    }
}
