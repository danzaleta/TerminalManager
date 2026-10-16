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
