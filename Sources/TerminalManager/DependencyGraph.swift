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
        
        let selfSize = pkg.installed.compactMap { $0.installed_size }.reduce(0, +)
        
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
