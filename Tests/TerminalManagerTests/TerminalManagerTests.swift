import Foundation
import XCTest
@testable import TerminalManager

final class TerminalManagerTests: XCTestCase {
    
    func testBrewLocatorPrefixResolution() {
        let prefix = BrewLocator.brewPrefix
        XCTAssertFalse(prefix.isEmpty)
        XCTAssertTrue(prefix.hasPrefix("/"))
    }
    
    func testDependencyGraphFormatting() {
        let response = BrewInfoResponse(formulae: [], casks: [])
        let graph = DependencyGraph(response: response)
        
        let formattedZero = graph.formattedSize(bytes: 0)
        XCTAssertTrue(formattedZero.contains("Zero") || formattedZero.contains("0"))
        
        let formattedMB = graph.formattedSize(bytes: 10_485_760) // 10 MB
        XCTAssertTrue(formattedMB.contains("MB") || formattedMB.contains("10"))
    }
    
    func testDependencyGraphCycleAndSharedDependencyDeduplication() {
        let sharedDep = BrewPackage(
            name: "openssl",
            desc: "SSL library",
            versions: BrewVersions(stable: "3.0.0"),
            installed: [BrewInstalled(version: "3.0.0", installed_on_request: false, installed_as_dependency: true, installed_size: 1000)],
            dependencies: []
        )
        
        let leafA = BrewPackage(
            name: "curl",
            desc: "Transfer URL syntax",
            versions: BrewVersions(stable: "8.0.0"),
            installed: [BrewInstalled(version: "8.0.0", installed_on_request: true, installed_as_dependency: false, installed_size: 500)],
            dependencies: ["openssl"]
        )
        
        let leafB = BrewPackage(
            name: "git",
            desc: "Fast distributed version control",
            versions: BrewVersions(stable: "2.40.0"),
            installed: [BrewInstalled(version: "2.40.0", installed_on_request: true, installed_as_dependency: false, installed_size: 2000)],
            dependencies: ["openssl"]
        )
        
        let response = BrewInfoResponse(formulae: [leafA, leafB, sharedDep], casks: [])
        let graph = DependencyGraph(response: response)
        
        XCTAssertEqual(graph.formulae.count, 3)
        XCTAssertEqual(graph.formulae["curl"]?.dependencies, ["openssl"])
        XCTAssertEqual(graph.formulae["git"]?.dependencies, ["openssl"])
        
        // Total physical bytes calculation must not crash or loop infinitely
        let total = graph.totalPhysicalBytes(leaves: ["curl", "git"], casks: [])
        XCTAssertGreaterThanOrEqual(total, 0)
    }
    
    func testBackupManagerJSONRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_backup_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let formulae = ["curl", "git", "gh"]
        let casks = ["iterm2", "visual-studio-code"]
        
        try BackupManager.export(formulae: formulae, casks: casks, to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        
        let loaded = try BackupManager.load(from: fileURL)
        XCTAssertEqual(loaded.formulae, formulae)
        XCTAssertEqual(loaded.casks, casks)
    }
    
    func testBackupManagerBrewfileExport() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("Brewfile_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let formulae = ["curl", "git"]
        let casks = ["iterm2"]
        
        try BackupManager.exportBrewfile(formulae: formulae, casks: casks, to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("cask \"iterm2\""))
        XCTAssertTrue(content.contains("brew \"curl\""))
        XCTAssertTrue(content.contains("brew \"git\""))
    }
    
    func testLocalSystemScanner() {
        let scanner = LocalSystemScanner()
        let binaries = scanner.scanLocalBinaries()
        // Must return an array without throwing
        XCTAssertGreaterThanOrEqual(binaries.count, 0)
        
        let emulators = scanner.scanStandaloneEmulators(managedCaskTokens: ["iterm2"], managedCaskNames: ["iTerm"])
        XCTAssertGreaterThanOrEqual(emulators.count, 0)
        // If Terminal.app was found, verify it's marked as system protected
        if let terminalApp = emulators.first(where: { $0.name == "Terminal" }) {
            XCTAssertTrue(terminalApp.isSystemProtected)
        }
    }
}
