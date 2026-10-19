import Foundation
import AppKit

public struct StandaloneAppItem: Identifiable, Sendable {
    public var id: String { bundlePath }
    public let name: String
    public let bundlePath: String
    public let sizeBytes: Int
    public let isSystemProtected: Bool
}

public struct LocalBinaryItem: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let path: String
    public let targetPath: String?
    public let sizeBytes: Int
}

public struct NvmNodeItem: Identifiable, Sendable {
    public var id: String { path }
    public let version: String
    public let path: String
    public let isDefault: Bool
    public let sizeBytes: Int
}

public struct NpmGlobalPackageItem: Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let version: String
    public let description: String
    public let path: String
    public let nodeLabel: String
    public let npmBinaryPath: String
    public let sizeBytes: Int
    public let isInsideNvm: Bool
}

public struct PyenvPythonItem: Identifiable, Sendable {
    public var id: String { path }
    public let version: String
    public let path: String
    public let isDefault: Bool
    public let sizeBytes: Int
}

public struct PipPackageItem: Identifiable, Sendable {
    public var id: String { distInfoPath }
    public let name: String
    public let version: String
    public let description: String
    public let distInfoPath: String
    public let pythonLabel: String
    public let pipBinaryPath: String
    public let sizeBytes: Int
}

private struct NpmPackageJSON: Decodable {
    let name: String?
    let version: String?
    let description: String?
}

public struct LocalSystemScanner: Sendable {
    public init() {}
    
    public static let knownEmulatorNames = [
        "Terminal",
        "iTerm",
        "Warp",
        "Ghostty",
        "kitty",
        "Alacritty",
        "WezTerm",
        "Hyper",
        "Tabby",
        "Rio"
    ]
    
    /// Scans standard locations for terminal applications that are NOT managed by Homebrew Casks.
    public func scanStandaloneEmulators(managedCaskTokens: Set<String>, managedCaskNames: Set<String>) -> [StandaloneAppItem] {
        var items: [StandaloneAppItem] = []
        let homeDir = NSHomeDirectory()
        let searchDirs = [
            "/Applications",
            "\(homeDir)/Applications",
            "/System/Applications/Utilities"
        ]
        
        var seenBundlePaths = Set<String>()
        
        for dir in searchDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for file in files where file.hasSuffix(".app") {
                let baseName = String(file.dropLast(4))
                
                // Check if it matches known emulators
                let isKnownEmulator = Self.knownEmulatorNames.contains { emulator in
                    baseName.localizedCaseInsensitiveContains(emulator)
                }
                guard isKnownEmulator else { continue }
                
                let fullPath = "\(dir)/\(file)"
                if seenBundlePaths.contains(fullPath) { continue }
                seenBundlePaths.insert(fullPath)
                
                // Exclude if already managed by a cask
                let baseLower = baseName.lowercased()
                let isManagedByCask = managedCaskTokens.contains { $0.lowercased() == baseLower } ||
                                      managedCaskNames.contains { $0.lowercased() == baseLower }
                if isManagedByCask { continue }
                
                let isProtected = fullPath.hasPrefix("/System/") || baseName == "Terminal"
                let size = calculateDirectorySize(atPath: fullPath)
                
                items.append(StandaloneAppItem(
                    name: baseName,
                    bundlePath: fullPath,
                    sizeBytes: size,
                    isSystemProtected: isProtected
                ))
            }
        }
        
        return items.sorted { $0.name < $1.name }
    }
    
    /// Scans ~/.local/bin for user-installed binaries or symlinks (e.g. claude, agy, vtex).
    public func scanLocalBinaries() -> [LocalBinaryItem] {
        var items: [LocalBinaryItem] = []
        let homeDir = NSHomeDirectory()
        let localBinDir = "\(homeDir)/.local/bin"
        
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: localBinDir) else {
            return []
        }
        
        for file in files where !file.hasPrefix(".") {
            let fullPath = "\(localBinDir)/\(file)"
            let targetPath = try? FileManager.default.destinationOfSymbolicLink(atPath: fullPath)
            
            var totalSize = 0
            if let target = targetPath {
                let resolved = target.hasPrefix("/") ? target : "\(localBinDir)/\(target)"
                totalSize += calculateFileSize(atPath: resolved)
            } else {
                totalSize += calculateFileSize(atPath: fullPath)
            }
            
            // If claude binary, also include ~/.local/share/claude data if present
            if file == "claude" {
                let shareDir = "\(homeDir)/.local/share/claude"
                if FileManager.default.fileExists(atPath: shareDir) {
                    totalSize += calculateDirectorySize(atPath: shareDir)
                }
            }
            
            items.append(LocalBinaryItem(
                name: file,
                path: fullPath,
                targetPath: targetPath,
                sizeBytes: totalSize
            ))
        }
        
        return items.sorted { $0.name < $1.name }
    }
    
    /// Scans ~/.nvm/versions/node for installed Node.js runtimes and global npm packages across NVM and Homebrew.
    public func scanNvmAndNpm() -> (nvmNodes: [NvmNodeItem], npmGlobals: [NpmGlobalPackageItem]) {
        let homeDir = NSHomeDirectory()
        let nvmDir = ProcessInfo.processInfo.environment["NVM_DIR"] ?? "\(homeDir)/.nvm"
        let versionsDir = "\(nvmDir)/versions/node"
        
        let defaultAliasPath = "\(nvmDir)/alias/default"
        let rawDefaultAlias = (try? String(contentsOfFile: defaultAliasPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        var nvmNodes: [NvmNodeItem] = []
        var npmGlobals: [NpmGlobalPackageItem] = []
        
        // 1. Scan NVM Node versions and their global node_modules
        if let versionFolders = try? FileManager.default.contentsOfDirectory(atPath: versionsDir) {
            for folder in versionFolders where folder.hasPrefix("v") {
                let nodePath = "\(versionsDir)/\(folder)"
                let isDefault = !rawDefaultAlias.isEmpty && (
                    folder == rawDefaultAlias ||
                    folder == "v\(rawDefaultAlias)" ||
                    folder.hasPrefix("v\(rawDefaultAlias).")
                )
                
                let nodeSize = calculateDirectorySize(atPath: nodePath)
                nvmNodes.append(NvmNodeItem(
                    version: folder,
                    path: nodePath,
                    isDefault: isDefault,
                    sizeBytes: nodeSize
                ))
                
                let nodeModulesPath = "\(nodePath)/lib/node_modules"
                let npmBin = "\(nodePath)/bin/npm"
                let foundGlobals = scanNodeModulesDirectory(
                    atPath: nodeModulesPath,
                    nodeLabel: "NVM \(folder)",
                    npmBinaryPath: npmBin,
                    isInsideNvm: true
                )
                npmGlobals.append(contentsOf: foundGlobals)
            }
        }
        
        // 2. Scan Homebrew global node_modules (/opt/homebrew/lib/node_modules or /usr/local/lib/node_modules)
        let brewPrefix = BrewLocator.brewPrefix
        let brewNodeModules = "\(brewPrefix)/lib/node_modules"
        let brewNpmBin = "\(brewPrefix)/bin/npm"
        if FileManager.default.fileExists(atPath: brewNodeModules) {
            let brewGlobals = scanNodeModulesDirectory(
                atPath: brewNodeModules,
                nodeLabel: "Homebrew Node",
                npmBinaryPath: brewNpmBin,
                isInsideNvm: false
            )
            npmGlobals.append(contentsOf: brewGlobals)
        }
        
        nvmNodes.sort { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
        npmGlobals.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        return (nvmNodes, npmGlobals)
    }
    
    private func scanNodeModulesDirectory(
        atPath nodeModulesPath: String,
        nodeLabel: String,
        npmBinaryPath: String,
        isInsideNvm: Bool
    ) -> [NpmGlobalPackageItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: nodeModulesPath) else {
            return []
        }
        
        let builtInPackages: Set<String> = ["npm", "corepack"]
        var results: [NpmGlobalPackageItem] = []
        
        for entry in entries where !entry.hasPrefix(".") {
            if builtInPackages.contains(entry) { continue }
            
            let fullEntryPath = "\(nodeModulesPath)/\(entry)"
            if entry.hasPrefix("@") {
                // Scoped package directory (e.g. @playwright/cli)
                guard let scopedEntries = try? FileManager.default.contentsOfDirectory(atPath: fullEntryPath) else { continue }
                for subEntry in scopedEntries where !subEntry.hasPrefix(".") {
                    let pkgPath = "\(fullEntryPath)/\(subEntry)"
                    let pkgName = "\(entry)/\(subEntry)"
                    if let item = buildNpmPackageItem(
                        defaultName: pkgName,
                        pkgPath: pkgPath,
                        nodeLabel: nodeLabel,
                        npmBinaryPath: npmBinaryPath,
                        isInsideNvm: isInsideNvm
                    ) {
                        results.append(item)
                    }
                }
            } else {
                if let item = buildNpmPackageItem(
                    defaultName: entry,
                    pkgPath: fullEntryPath,
                    nodeLabel: nodeLabel,
                    npmBinaryPath: npmBinaryPath,
                    isInsideNvm: isInsideNvm
                ) {
                    results.append(item)
                }
            }
        }
        
        return results
    }
    
    private func buildNpmPackageItem(
        defaultName: String,
        pkgPath: String,
        nodeLabel: String,
        npmBinaryPath: String,
        isInsideNvm: Bool
    ) -> NpmGlobalPackageItem? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: pkgPath, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        
        let packageJsonPath = "\(pkgPath)/package.json"
        var name = defaultName
        var version = ""
        var desc = "Global npm package"
        
        if let data = try? Data(contentsOf: URL(fileURLWithPath: packageJsonPath)),
           let decoded = try? JSONDecoder().decode(NpmPackageJSON.self, from: data) {
            if let n = decoded.name, !n.isEmpty { name = n }
            if let v = decoded.version, !v.isEmpty { version = v }
            if let d = decoded.description, !d.isEmpty { desc = d }
        }
        
        let size = calculateDirectorySize(atPath: pkgPath)
        let fullDesc = version.isEmpty ? desc : "v\(version) · \(desc)"
        
        return NpmGlobalPackageItem(
            name: name,
            version: version,
            description: fullDesc,
            path: pkgPath,
            nodeLabel: nodeLabel,
            npmBinaryPath: npmBinaryPath,
            sizeBytes: size,
            isInsideNvm: isInsideNvm
        )
    }
    
    /// Scans `~/.pyenv/versions` for installed Python runtimes and user-requested `pip` packages (PEP 376 `REQUESTED` marker).
    public func scanPyenvAndPip() -> (pyenvPythons: [PyenvPythonItem], pipPackages: [PipPackageItem]) {
        var pyenvPythons: [PyenvPythonItem] = []
        var pipPackages: [PipPackageItem] = []
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pyenvDir = "\(home)/.pyenv"
        let pyenvVersionsDir = "\(pyenvDir)/versions"
        
        let defaultVersion: String? = {
            let verFile = "\(pyenvDir)/version"
            guard let raw = try? String(contentsOfFile: verFile, encoding: .utf8) else { return nil }
            let trimmed = raw.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }()
        
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: pyenvVersionsDir) else {
            return ([], [])
        }
        
        let sortedVersions = versions.filter { !$0.hasPrefix(".") }.sorted {
            $0.localizedStandardCompare($1) == .orderedDescending
        }
        
        let builtInPackages: Set<String> = ["pip", "setuptools", "wheel"]
        
        for ver in sortedVersions {
            let verPath = "\(pyenvVersionsDir)/\(ver)"
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: verPath, isDirectory: &isDir), isDir.boolValue else { continue }
            
            // Skip virtualenvs that are symlinks unless they are real directories
            if let attrs = try? FileManager.default.attributesOfItem(atPath: verPath),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                continue
            }
            
            let totalSize = calculateDirectorySize(atPath: verPath)
            let isDefault = (defaultVersion == ver)
            
            pyenvPythons.append(PyenvPythonItem(
                version: ver,
                path: verPath,
                isDefault: isDefault,
                sizeBytes: totalSize
            ))
            
            let pipBin = "\(verPath)/bin/pip"
            let libDir = "\(verPath)/lib"
            guard let libEntries = try? FileManager.default.contentsOfDirectory(atPath: libDir) else { continue }
            
            for libEntry in libEntries where libEntry.hasPrefix("python") {
                let sitePackagesDir = "\(libDir)/\(libEntry)/site-packages"
                guard let spEntries = try? FileManager.default.contentsOfDirectory(atPath: sitePackagesDir) else { continue }
                
                for spEntry in spEntries where spEntry.hasSuffix(".dist-info") {
                    let distInfoPath = "\(sitePackagesDir)/\(spEntry)"
                    let requestedFile = "\(distInfoPath)/REQUESTED"
                    guard FileManager.default.fileExists(atPath: requestedFile) else { continue }
                    
                    let meta = parsePipMetadata(atPath: "\(distInfoPath)/METADATA", fallbackDirName: spEntry)
                    if builtInPackages.contains(meta.name.lowercased()) { continue }
                    
                    let pkgSize = calculatePipPackageSize(
                        sitePackagesDir: sitePackagesDir,
                        distInfoPath: distInfoPath
                    )
                    let fullDesc = meta.version.isEmpty ? meta.summary : "v\(meta.version) · \(meta.summary)"
                    
                    pipPackages.append(PipPackageItem(
                        name: meta.name,
                        version: meta.version,
                        description: fullDesc,
                        distInfoPath: distInfoPath,
                        pythonLabel: "Python \(ver)",
                        pipBinaryPath: pipBin,
                        sizeBytes: pkgSize
                    ))
                }
            }
        }
        
        return (pyenvPythons, pipPackages)
    }
    
    private func parsePipMetadata(atPath metadataPath: String, fallbackDirName: String) -> (name: String, version: String, summary: String) {
        let baseFallback = fallbackDirName.replacingOccurrences(of: ".dist-info", with: "")
        var name = baseFallback
        var version = ""
        var summary = "Pip package"
        
        guard let content = try? String(contentsOfFile: metadataPath, encoding: .utf8) else {
            return (name, version, summary)
        }
        
        for line in content.components(separatedBy: .newlines) {
            if line.isEmpty { break } // End of RFC 822 headers in METADATA
            if line.hasPrefix("Name: ") {
                name = String(line.dropFirst("Name: ".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Version: ") {
                version = String(line.dropFirst("Version: ".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Summary: ") {
                let s = String(line.dropFirst("Summary: ".count)).trimmingCharacters(in: .whitespaces)
                if !s.isEmpty && s != "UNKNOWN" {
                    summary = s
                }
            }
        }
        return (name, version, summary)
    }
    
    private func calculatePipPackageSize(sitePackagesDir: String, distInfoPath: String) -> Int {
        let recordPath = "\(distInfoPath)/RECORD"
        guard let content = try? String(contentsOfFile: recordPath, encoding: .utf8) else {
            return calculateDirectorySize(atPath: distInfoPath)
        }
        
        var total = 0
        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count >= 3, let bytes = Int(parts[2].trimmingCharacters(in: .whitespaces)) {
                total += bytes
            } else if let firstPart = parts.first, !firstPart.isEmpty {
                let filePath = "\(sitePackagesDir)/\(firstPart)"
                total += calculateFileSize(atPath: filePath)
            }
        }
        return total > 0 ? total : calculateDirectorySize(atPath: distInfoPath)
    }
    
    private func calculateDirectorySize(atPath path: String) -> Int {
        let url = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total = 0
        for case let fileURL as URL in enumerator {
            if let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = res.fileSize {
                total += size
            }
        }
        return total
    }
    
    private func calculateFileSize(atPath path: String) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int else {
            return 0
        }
        return size
    }
}

