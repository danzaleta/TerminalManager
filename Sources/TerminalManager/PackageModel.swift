import Foundation

public struct BrewInfoResponse: Codable, Sendable {
    public let formulae: [BrewPackage]
    public let casks: [BrewCask]
    
    public init(formulae: [BrewPackage] = [], casks: [BrewCask] = []) {
        self.formulae = formulae
        self.casks = casks
    }
}

public struct BrewPackage: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let desc: String?
    public let versions: BrewVersions
    public let installed: [BrewInstalled]
    public let dependencies: [String]
    
    public init(
        name: String,
        desc: String?,
        versions: BrewVersions,
        installed: [BrewInstalled],
        dependencies: [String]
    ) {
        self.name = name
        self.desc = desc
        self.versions = versions
        self.installed = installed
        self.dependencies = dependencies
    }
}

public struct BrewVersions: Codable, Sendable {
    public let stable: String?
    
    public init(stable: String?) {
        self.stable = stable
    }
}

public struct BrewInstalled: Codable, Sendable {
    public let version: String
    public let installed_on_request: Bool?
    public let installed_as_dependency: Bool?
    public let installed_size: Int?
    
    public init(version: String, installed_on_request: Bool?, installed_as_dependency: Bool?, installed_size: Int?) {
        self.version = version
        self.installed_on_request = installed_on_request
        self.installed_as_dependency = installed_as_dependency
        self.installed_size = installed_size
    }
}

public struct BrewCask: Codable, Identifiable, Sendable {
    public var id: String { token }
    public let token: String
    public let name: [String]?
    public let desc: String?
    public let version: String?
    public let installed: String?
    
    public var displayName: String {
        name?.first ?? token
    }
    
    public init(token: String, name: [String]?, desc: String?, version: String?, installed: String?) {
        self.token = token
        self.name = name
        self.desc = desc
        self.version = version
        self.installed = installed
    }
}

public struct BrewOutdatedResponse: Codable, Sendable {
    public let formulae: [OutdatedFormula]
    public let casks: [OutdatedCask]
    
    public init(formulae: [OutdatedFormula] = [], casks: [OutdatedCask] = []) {
        self.formulae = formulae
        self.casks = casks
    }
}

public struct OutdatedFormula: Codable, Sendable {
    public let name: String
    public let current_version: String
}

public struct OutdatedCask: Codable, Sendable {
    public let name: String
    public let current_version: String
}

public enum PackageKind: String, Sendable {
    case formula
    case cask
    case standaloneApp
    case localBinary
    case nvmNode
    case npmGlobal
}

public struct PackageDisplayItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let sizeString: String
    public let rawBytes: Int
    public let kind: PackageKind
    public let outdatedVersion: String?
    public let isSystemProtected: Bool
    public let filePath: String?
    public let badgeText: String?
    public let npmBinaryPath: String?
    
    public var isCask: Bool { kind == .cask }
    public var isStandaloneApp: Bool { kind == .standaloneApp }
    public var isLocalBinary: Bool { kind == .localBinary }
    public var isNvmNode: Bool { kind == .nvmNode }
    public var isNpmGlobal: Bool { kind == .npmGlobal }
    public var hasUpdate: Bool { outdatedVersion != nil }
    
    public init(
        id: String,
        name: String,
        description: String,
        sizeString: String,
        rawBytes: Int = 0,
        kind: PackageKind = .formula,
        outdatedVersion: String? = nil,
        isSystemProtected: Bool = false,
        filePath: String? = nil,
        badgeText: String? = nil,
        npmBinaryPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sizeString = sizeString
        self.rawBytes = rawBytes
        self.kind = kind
        self.outdatedVersion = outdatedVersion
        self.isSystemProtected = isSystemProtected
        self.filePath = filePath
        self.badgeText = badgeText
        self.npmBinaryPath = npmBinaryPath
    }
    
    public init(id: String, name: String, description: String, sizeString: String, rawBytes: Int = 0, isCask: Bool) {
        self.init(
            id: id,
            name: name,
            description: description,
            sizeString: sizeString,
            rawBytes: rawBytes,
            kind: isCask ? .cask : .formula
        )
    }
}
