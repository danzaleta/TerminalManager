import Foundation

public struct BrewInfoResponse: Codable {
    public let formulae: [BrewPackage]
    public let casks: [BrewCask]
}

public struct BrewPackage: Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let desc: String?
    public let versions: BrewVersions
    public let installed: [BrewInstalled]
    public let dependencies: [String]
    
    // Extracted size from installed array
    public var totalSize: String? {
        // e.g. "installed": [{"installed_as_dependency": false, "installed_on_request": true, "poured_from_bottle": true, "time": 1690000000, "runtime_dependencies": [], "installed_folder": "/opt/homebrew/Cellar/...", "built_as_bottle": true, "installed_size": 123456}]
        // We will sum the sizes
        return nil
    }
}

public struct BrewVersions: Codable {
    public let stable: String?
}

public struct BrewInstalled: Codable {
    public let version: String
    public let installed_on_request: Bool?
    public let installed_as_dependency: Bool?
    public let installed_size: Int?
}

public struct BrewCask: Codable, Identifiable {
    public var id: String { token }
    public let token: String
    public let name: [String]
    public let desc: String?
    public let version: String
}
