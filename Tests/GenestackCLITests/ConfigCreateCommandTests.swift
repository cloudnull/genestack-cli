//
// ConfigCreateCommandTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl
import Foundation
import Yams

final class ConfigCreateCommandTests: XCTestCase {
    
    func testCreateMinimalSpec() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let outputPath = tempDir.appendingPathComponent("genestack-cluster.yaml").path
        
        let args: [String] = [
            "--yes",
            "--cluster-name", "testcluster",
            "--gateway-domain", "test.local",
            "--acme-email", "admin@test.local",
            "--output", outputPath
        ]
        
        var command = try ConfigCreateCommand.parse(args)
        try command.run()
        
        // Verify the spec was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
        
        let content = try String(contentsOfFile: outputPath)
        let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        XCTAssertEqual(spec.version, "1.0")
        XCTAssertEqual(spec.metadata.clusterName, "testcluster")
        XCTAssertEqual(spec.metadata.gatewayDomain, "test.local")
        XCTAssertEqual(spec.metadata.acmeEmail, "admin@test.local")
        XCTAssertFalse(spec.kubernetes?.hyperconverged ?? true)
        XCTAssertTrue(spec.nodes?.isEmpty ?? true)
        XCTAssertTrue(spec.services?.isEmpty ?? true)
    }
    
    func testCreateHyperconvergedSpec() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let outputPath = tempDir.appendingPathComponent("hypercloud.yaml").path
        
        let args: [String] = [
            "--yes",
            "--hyperconverged",
            "--cluster-name", "hypercloud",
            "--output", outputPath
        ]
        
        var command = try ConfigCreateCommand.parse(args)
        try command.run()
        
        let content = try String(contentsOfFile: outputPath)
        let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        XCTAssertTrue(spec.kubernetes?.hyperconverged ?? false)
        XCTAssertEqual(spec.nodes?.count, 3)
        
        let expectedRoles = ["control-plane", "etcd", "kube-node", "openstack-control-plane", "openstack-compute-node", "openstack-network-node", "openstack-storage-node"]
        for node in spec.nodes ?? [] {
            for role in expectedRoles {
                XCTAssertTrue(node.roles.contains(role), "Node \(node.name) missing role \(role)")
            }
        }
        
        XCTAssertNotNil(spec.kubernetes?.groupVars)
        XCTAssertNotNil(spec.kubernetes?.groupVars?["openstack_compute_nodes"])
    }
    
    func testCreateHyperconvergedNodesHaveCorrectAddresses() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let outputPath = tempDir.appendingPathComponent("hypercloud.yaml").path
        
        let args: [String] = [
            "--yes",
            "--hyperconverged",
            "--cluster-name", "hypercloud",
            "--output", outputPath
        ]
        
        var command = try ConfigCreateCommand.parse(args)
        try command.run()
        
        let content = try String(contentsOfFile: outputPath)
        let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        XCTAssertEqual(spec.nodes?.count, 3)
        for (index, node) in (spec.nodes ?? []).enumerated() {
            XCTAssertEqual(node.name, "node0\(index + 1).hypercloud.local")
            XCTAssertNotNil(node.addresses?["ansible_host"])
            XCTAssertNotNil(node.addresses?["management_ip"])
            XCTAssertNotNil(node.addresses?["network_mgmt_address"])
        }
    }
    
    func testCreateOverwritesWithYesFlag() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let outputPath = tempDir.appendingPathComponent("genestack-cluster.yaml").path
        try "existing content".write(toFile: outputPath, atomically: true, encoding: .utf8)
        
        let args: [String] = [
            "--yes",
            "--cluster-name", "newcluster",
            "--output", outputPath
        ]
        
        var command = try ConfigCreateCommand.parse(args)
        try command.run()
        
        let content = try String(contentsOfFile: outputPath)
        XCTAssertTrue(content.contains("newcluster"))
        XCTAssertFalse(content.contains("existing content"))
    }
    
    func testCreateWithCustomKubeVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let outputPath = tempDir.appendingPathComponent("genestack-cluster.yaml").path
        
        let args: [String] = [
            "--yes",
            "--cluster-name", "test",
            "--kube-version", "v1.31.0",
            "--output", outputPath
        ]
        
        var command = try ConfigCreateCommand.parse(args)
        try command.run()
        
        let content = try String(contentsOfFile: outputPath)
        let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        XCTAssertEqual(spec.kubernetes?.kubeVersion, "v1.31.0")
    }
    
    func testCreateWithoutYesFailsOnExistingFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let outputPath = tempDir.appendingPathComponent("existing.yaml").path
        try "existing content".write(toFile: outputPath, atomically: true, encoding: .utf8)
        
        let args: [String] = [
            "--cluster-name", "test",
            "--output", outputPath
            // Intentionally missing --yes flag
        ]
        
        var command = try ConfigCreateCommand.parse(args)
        XCTAssertThrowsError(try command.run())
    }
}
