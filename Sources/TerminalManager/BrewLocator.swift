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
}
