//
// NodeCommandsTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl
import Foundation
import Yams

final class NodeCommandsTests: XCTestCase {
    
    func testNodeListCommandLogic() throws {
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
nodes:
  - name: node01.test.local
    ip: 10.0.0.10
    roles: [control-plane]
    labels:
      zone: us-west
  - name: node02.test.local
    ip: 10.0.0.11
    roles: [worker]
"""
        let specPath = tempDir.appendingPathComponent("genestack-cluster.yaml")
        try specYAML.write(to: specPath, atomically: true, encoding: .utf8)
        
        let content = try String(contentsOfFile: specPath.path)
        let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        // Test that the spec was parsed correctly
        XCTAssertEqual(spec.nodes?.count, 2)
        XCTAssertEqual(spec.nodes?[0].name, "node01.test.local")
        XCTAssertEqual(spec.nodes?[1].name, "node02.test.local")
        XCTAssertEqual(spec.nodes?[0].labels?["zone"], "us-west")
    }
    
    func testNodeAddCommandLogic() throws {
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
"""
        let specPath = tempDir.appendingPathComponent("genestack-cluster.yaml")
        try specYAML.write(to: specPath, atomically: true, encoding: .utf8)
        
        // Load spec, add node
        let content = try String(contentsOfFile: specPath.path)
        var spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        let newNode = NodeSpec(
            name: "node03.test.local",
            ip: "10.0.0.12",
            roles: ["control-plane", "kube-node"],
            labels: nil,
            taints: nil,
            addresses: ["ansible_host": "10.0.0.12"]
        )
        
        spec.nodes?.append(newNode)
        
        let yaml = try YAMLEncoder().encode(spec)
        try yaml.write(to: specPath, atomically: true, encoding: .utf8)
        
        // Verify the node was added
        let updatedContent = try String(contentsOfFile: specPath.path)
        let updatedSpec = try YAMLDecoder().decode(ClusterSpec.self, from: updatedContent)
        
        XCTAssertEqual(updatedSpec.nodes?.count, 1)
        XCTAssertEqual(updatedSpec.nodes?[0].name, "node03.test.local")
        XCTAssertEqual(updatedSpec.nodes?[0].ip, "10.0.0.12")
        XCTAssertEqual(updatedSpec.nodes?[0].roles.count, 2)
    }
    
    func testNodeRemoveCommandLogic() throws {
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
nodes:
  - name: node01.test.local
    ip: 10.0.0.10
    roles: [control-plane]
  - name: node02.test.local
    ip: 10.0.0.11
    roles: [worker]
"""
        
        let specPath = tempDir.appendingPathComponent("genestack-cluster.yaml")
        try specYAML.write(to: specPath, atomically: true, encoding: .utf8)
        
        // Load spec, remove node
        let content = try String(contentsOfFile: specPath.path)
        var spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        let index = spec.nodes?.firstIndex(where: { $0.name == "node01.test.local" })
        spec.nodes?.remove(at: index!)
        
        let yaml = try YAMLEncoder().encode(spec)
        try yaml.write(to: specPath, atomically: true, encoding: .utf8)
        
        // Verify the node was removed
        let updatedContent = try String(contentsOfFile: specPath.path)
        let updatedSpec = try YAMLDecoder().decode(ClusterSpec.self, from: updatedContent)
        
        XCTAssertEqual(updatedSpec.nodes?.count, 1)
        XCTAssertEqual(updatedSpec.nodes?[0].name, "node02.test.local")
    }
}
