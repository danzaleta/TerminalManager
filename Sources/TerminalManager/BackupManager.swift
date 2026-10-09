import Foundation
import SwiftUI

public struct BackupData: Codable {
    public let formulae: [String]
    public let casks: [String]
    public let timestamp: Date
}

public class BackupManager {
    public static func export(formulae: [String], casks: [String], to url: URL) throws {
        let data = BackupData(formulae: formulae, casks: casks, timestamp: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)
    }
    
    public static func load(from url: URL) throws -> BackupData {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(BackupData.self, from: data)
    }
}
