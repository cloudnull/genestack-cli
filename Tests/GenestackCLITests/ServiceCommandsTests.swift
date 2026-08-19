//
// ServiceCommandsTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl
import Foundation
import Yams

final class ServiceCommandsTests: XCTestCase {
    
    func testServiceRemoveDisablesService() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let specYAML = """
version: "1.0"
metadata:
  cluster_name: testcloud
  gateway_domain: test.local
nodes: []
services:
  - name: keystone
    enabled: true
  - name: nova
    enabled: false
"""
        let specPath = tempDir.appendingPathComponent("genestack-cluster.yaml")
        try specYAML.write(to: specPath, atomically: true, encoding: .utf8)
        
        // Load spec, modify it (simulate disabling)
        let content = try String(contentsOfFile: specPath.path)
        var spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        // Disable keystone
        if let services = spec.services, let index = services.firstIndex(where: { $0.name == "keystone" }) {
            var newServices = services
            newServices[index] = ServiceSpec(
                name: services[index].name,
                enabled: false,
                version: services[index].version,
                helmArgs: services[index].helmArgs
            )
            spec.services = newServices
        }
        
        // Save back
        let yaml = try YAMLEncoder().encode(spec)
        try yaml.write(to: specPath, atomically: true, encoding: .utf8)
        
        // Verify the service was disabled
        let updatedContent = try String(contentsOfFile: specPath.path)
        let updatedSpec = try YAMLDecoder().decode(ClusterSpec.self, from: updatedContent)
        
        let keystone = updatedSpec.services?.first { $0.name == "keystone" }
        XCTAssertFalse(keystone?.enabled ?? true)
    }
    
    func testServicePurgeRemovesService() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let specYAML = """
version: "1.0"
metadata:
  cluster_name: testcloud
  gateway_domain: test.local
nodes: []
services:
  - name: keystone
    enabled: true
  - name: nova
    enabled: false
"""
        
        let specPath = tempDir.appendingPathComponent("genestack-cluster.yaml")
        try specYAML.write(to: specPath, atomically: true, encoding: .utf8)
        
        // Load spec, remove service (simulate purge)
        let content = try String(contentsOfFile: specPath.path)
        var spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        let index = spec.services?.firstIndex(where: { $0.name == "nova" })
        spec.services?.remove(at: index!)
        
        // Save back
        let yaml = try YAMLEncoder().encode(spec)
        try yaml.write(to: specPath, atomically: true, encoding: .utf8)
        
        // Verify the service was removed entirely
        let updatedContent = try String(contentsOfFile: specPath.path)
        let updatedSpec = try YAMLDecoder().decode(ClusterSpec.self, from: updatedContent)
        
        XCTAssertNil(updatedSpec.services?.first { $0.name == "nova" })
        XCTAssertEqual(updatedSpec.services?.count, 1)
    }
}
