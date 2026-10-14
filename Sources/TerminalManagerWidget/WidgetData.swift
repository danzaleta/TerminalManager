import Foundation

public struct WidgetData: Codable, Sendable {
    public let appsCount: Int
    public let packagesCount: Int
    public let totalBytes: Int64
    public let formattedDiskSpace: String
    public let lastUpdated: Date
    
    public init(
        appsCount: Int,
        packagesCount: Int,
        totalBytes: Int64,
        formattedDiskSpace: String,
        lastUpdated: Date = Date()
    ) {
        self.appsCount = appsCount
        self.packagesCount = packagesCount
        self.totalBytes = totalBytes
        self.formattedDiskSpace = formattedDiskSpace
        self.lastUpdated = lastUpdated
    }
    
    public static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TerminalManager", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("widget_data.json")
    }
    
    public static func load() -> WidgetData? {
        let url = storageURL
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return nil
        }
        return decoded
    }
    
    public func save() {
        let url = Self.storageURL
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url)
        }
    }
}
