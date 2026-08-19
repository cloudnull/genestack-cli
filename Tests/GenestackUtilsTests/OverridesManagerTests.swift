//
// OverridesManagerTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl

final class OverridesManagerTests: XCTestCase {
    
    func testResolveOverridesDirDefault() {
        let manager = OverridesManager(genestackDir: "/opt/genestack")
        let result = manager.resolveOverridesDir(spec: nil, defaultDir: "/etc/genestack")
        XCTAssertEqual(result, "/etc/genestack")
    }
    
    func testResolveOverridesDirWithReplaceBase() {
        let manager = OverridesManager(genestackDir: "/opt/custom")
        let spec = OverridesSpec(repo: "https://github.com/test/overrides", ref: "main", replaceBase: true)
        let result = manager.resolveOverridesDir(spec: spec, defaultDir: "/etc/genestack")
        XCTAssertEqual(result, "/opt/custom")
    }
    
    func testResolveOverridesDirWithoutReplaceBase() {
        let manager = OverridesManager(genestackDir: "/opt/genestack")
        let spec = OverridesSpec(repo: "https://github.com/test/overrides", ref: "main", replaceBase: false)
        let result = manager.resolveOverridesDir(spec: spec, defaultDir: "/etc/genestack")
        XCTAssertEqual(result, "/etc/genestack")
    }
    
    func testSetupOverridesWithoutRepo() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let manager = OverridesManager(genestackDir: tempDir.path)
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "test", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let result = try manager.setupOverrides(spec: spec)
        XCTAssertEqual(result, "/etc/genestack")
    }
}
