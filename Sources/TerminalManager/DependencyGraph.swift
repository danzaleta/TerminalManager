import Foundation

public struct DependencyGraph {
    public let formulae: [String: BrewPackage]
    
    public init(response: BrewInfoResponse) {
        var map = [String: BrewPackage]()
        for f in response.formulae {
            map[f.name] = f
        }
        self.formulae = map
    }
    
    public func sizeOf(package name: String, visited: inout Set<String>) -> Int {
        if visited.contains(name) { return 0 }
        visited.insert(name)
        
        guard let pkg = formulae[name] else { return 0 }
        
        var selfSize = 0
        if let brewPrefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] ?? Optional("/opt/homebrew") {
            let url = URL(fileURLWithPath: "\(brewPrefix)/Cellar/\(name)")
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let fileSize = res.fileSize {
                        selfSize += fileSize
                    }
                }
            }
        }
        
        let depsSize = pkg.dependencies.reduce(0) { total, depName in
            total + sizeOf(package: depName, visited: &visited)
        }
        
        return selfSize + depsSize
    }
    
    public func formattedSize(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
