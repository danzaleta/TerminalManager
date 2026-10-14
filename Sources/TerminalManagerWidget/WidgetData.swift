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
    
    public static var fallbackURL: URL {
        return URL(fileURLWithPath: "/private/tmp/terminal_manager_widget.json")
    }
    
    public static func load() -> WidgetData? {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? decoder.decode(WidgetData.self, from: data) {
            return decoded
        }
        if let data = try? Data(contentsOf: fallbackURL),
           let decoded = try? decoder.decode(WidgetData.self, from: data) {
            return decoded
        }
        return nil
    }
    
    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.storageURL)
            try? data.write(to: Self.fallbackURL)
        }
    }
}
