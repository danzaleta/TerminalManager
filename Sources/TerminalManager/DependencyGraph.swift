import Foundation

public final class DependencyGraph: @unchecked Sendable {
    public let formulae: [String: BrewPackage]
    private let prefix: String
    private var kegSizeCache: [String: Int] = [:]
    private var caskSizeCache: [String: Int] = [:]
    private let lock = NSLock()
    
    public init(response: BrewInfoResponse, prefix: String = BrewLocator.brewPrefix) {
        var map = [String: BrewPackage]()
        for f in response.formulae {
            map[f.name] = f
        }
        self.formulae = map
        self.prefix = prefix
    }
    
    /// Returns the physical disk size of a single formula's keg in Cellar (excluding dependencies).
    public func selfSizeOf(package name: String) -> Int {
        lock.lock()
        if let cached = kegSizeCache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        var size = 0
        let kegURL = URL(fileURLWithPath: "\(prefix)/Cellar/\(name)")
        if let enumerator = FileManager.default.enumerator(at: kegURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let fileSize = res.fileSize {
                    size += fileSize
                }
            }
        }
        
        lock.lock()
        kegSizeCache[name] = size
        lock.unlock()
        return size
    }
    
    /// Returns the total size of a formula including all of its recursive dependencies.
    public func sizeOf(package name: String, visited: inout Set<String>) -> Int {
        if visited.contains(name) { return 0 }
        visited.insert(name)
        
        guard let pkg = formulae[name] else { return 0 }
        
        let selfSize = selfSizeOf(package: name)
        let depsSize = pkg.dependencies.reduce(0) { total, depName in
            total + sizeOf(package: depName, visited: &visited)
        }
        return selfSize + depsSize
    }
    
    /// Computes the true physical disk consumption across all leaves and casks without double counting shared dependencies.
    public func totalPhysicalBytes(leaves: [String], casks: [BrewCask]) -> Int64 {
        var globalVisited = Set<String>()
        var totalFormulaeBytes: Int64 = 0
        for leaf in leaves {
            totalFormulaeBytes += Int64(sizeOf(package: leaf, visited: &globalVisited))
        }
        
        var totalCaskBytes: Int64 = 0
        for cask in casks {
            totalCaskBytes += Int64(sizeOf(cask: cask))
        }
        return totalFormulaeBytes + totalCaskBytes
    }
    
    /// Finds and calculates the size of an installed cask app bundle or Caskroom payload.
    public func sizeOf(cask: BrewCask) -> Int {
        lock.lock()
        if let cached = caskSizeCache[cask.token] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        let homeDir = NSHomeDirectory()
        var candidatePaths: [String] = [
            "/Applications/\(cask.displayName).app",
            "/Applications/\(cask.token).app",
            "\(homeDir)/Applications/\(cask.displayName).app",
            "\(homeDir)/Applications/\(cask.token).app",
            "\(prefix)/Caskroom/\(cask.token)"
        ]
        
        // Accurate match against /Applications or ~/Applications (exact case-insensitive match only)
        let searchDirs = ["/Applications", "\(homeDir)/Applications"]
        for dir in searchDirs {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                for file in files where file.hasSuffix(".app") {
                    let base = String(file.dropLast(4)).lowercased()
                    let tokenLower = cask.token.lowercased()
                    let displayLower = cask.displayName.lowercased()
                    let slugged = displayLower.replacingOccurrences(of: " ", with: "-")
                    
                    if base == tokenLower || base == displayLower || base == slugged {
                        let fullPath = "\(dir)/\(file)"
                        if !candidatePaths.contains(fullPath) {
                            candidatePaths.insert(fullPath, at: 0)
                        }
                    }
                }
            }
        }
        
        var calculatedSize = 0
        for path in candidatePaths {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                let url = URL(fileURLWithPath: path)
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                    var total = 0
                    for case let fileURL as URL in enumerator {
                        if let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let fileSize = res.fileSize {
                            total += fileSize
                        }
                    }
                    if total > 0 {
                        calculatedSize = total
                        break
                    }
                }
            }
        }
        
        lock.lock()
        caskSizeCache[cask.token] = calculatedSize
        lock.unlock()
        return calculatedSize
    }
    
    public func formattedSize(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
