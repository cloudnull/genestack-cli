//
// ClusterSpecTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl
import Yams

final class ClusterSpecTests: XCTestCase {
    func testParseMinimalSpec() throws {
        let yaml = """
        version: "1.0"
        metadata:
          cluster_name: testcloud
          gateway_domain: test.local
        nodes: []
        services: []
        """
        
        let jsonData = try JSONSerialization.data(
            withJSONObject: try Yams.load(yaml: yaml) as! [String: Any],
            options: []
        )
        let spec = try JSONDecoder().decode(ClusterSpec.self, from: jsonData)
        
        XCTAssertEqual(spec.version, "1.0")
        XCTAssertEqual(spec.metadata.clusterName, "testcloud")
        XCTAssertEqual(spec.metadata.gatewayDomain, "test.local")
        XCTAssertTrue(spec.nodes.isEmpty)
        XCTAssertTrue(spec.services.isEmpty)
    }
    
    func testParseFullSpec() throws {
        let yaml = """
        version: "1.0"
        metadata:
          cluster_name: mycloud
          gateway_domain: cluster.local
          acme_email: admin@example.com
        overrides:
          repo: "https://github.com/rackerlabs/flex-overrides-template"
          ref: main
          replace_base: false
        kubernetes:
          hyperconverged: false
          kube_version: "v1.35.6"
          vars:
            cloud_name: mycloud-1
        nodes:
          - name: controller01.mycloud.local
            ip: 10.0.0.10
            roles: [control-plane, etcd, kube-node, openstack-control-plane]
            labels:
              node-role.kubernetes.io/worker: worker
            taints: []
            addresses:
              management_ip: 10.0.0.10
              ansible_host: 172.28.0.10
              network_mgmt_address: 172.28.0.10
        network:
          container_interface: bond0
          compute_interface: eth0
        storage:
          longhorn_replicas: 2
          cinder_backend: lvm
        services:
          - name: keystone
            enabled: true
            version: ~
            helm_args: []
        """
        
        let jsonData = try JSONSerialization.data(
            withJSONObject: try Yams.load(yaml: yaml) as! [String: Any],
            options: []
        )
        let spec = try JSONDecoder().decode(ClusterSpec.self, from: jsonData)
        
        // Verify basic fields
        XCTAssertEqual(spec.version, "1.0")
        XCTAssertEqual(spec.metadata.clusterName, "mycloud")
        XCTAssertEqual(spec.metadata.gatewayDomain, "cluster.local")
        XCTAssertEqual(spec.metadata.acmeEmail, "admin@example.com")
        
        // Verify overrides
        XCTAssertNotNil(spec.overrides)
        XCTAssertEqual(spec.overrides?.repo, "https://github.com/rackerlabs/flex-overrides-template")
        XCTAssertEqual(spec.overrides?.ref, "main")
        XCTAssertNotEqual(spec.overrides?.replaceBase, true)
        
        // Verify kubernetes
        XCTAssertNotNil(spec.kubernetes)
        XCTAssertEqual(spec.kubernetes?.hyperconverged, false)
        XCTAssertEqual(spec.kubernetes?.kubeVersion, "v1.35.6")
        
        // Verify nodes
        XCTAssertEqual(spec.nodes.count, 1)
        XCTAssertEqual(spec.nodes[0].name, "controller01.mycloud.local")
        XCTAssertEqual(spec.nodes[0].ip, "10.0.0.10")
        XCTAssertEqual(spec.nodes[0].roles.count, 4)
        XCTAssertTrue(spec.nodes[0].roles.contains("control-plane"))
        
        // Verify network
        XCTAssertNotNil(spec.network)
        XCTAssertEqual(spec.network?.containerInterface, "bond0")
        
        // Verify storage
        XCTAssertNotNil(spec.storage)
        XCTAssertEqual(spec.storage?.longhornReplicas, 2)
        XCTAssertEqual(spec.storage?.cinderBackend, "lvm")
        
        // Verify services
        XCTAssertEqual(spec.services.count, 1)
        XCTAssertEqual(spec.services[0].name, "keystone")
        XCTAssertTrue(spec.services[0].enabled)
    }
    
    func testLoadAndSaveRoundtrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let yamlContent = """
        version: "1.0"
        metadata:
          cluster_name: roundtrip-test
          gateway_domain: test.local
        nodes: []
        services:
          - name: keypool
            enabled: false
        """
        
        let inputPath = tempDir.appendingPathComponent("input.yaml")
        let outputPath = tempDir.appendingPathComponent("output.yaml")
        
        try yamlContent.write(to: inputPath, atomically: true, encoding: .utf8)
        
        let spec = try ClusterSpec.load(from: inputPath.path)
        
        try spec.save(to: outputPath.path)
        
        let reloadedSpec = try ClusterSpec.load(from: outputPath.path)
        
        XCTAssertEqual(spec.version, reloadedSpec.version)
        XCTAssertEqual(spec.metadata.clusterName, reloadedSpec.metadata.clusterName)
        XCTAssertEqual(spec.nodes.count, reloadedSpec.nodes.count)
        XCTAssertEqual(spec.services.count, reloadedSpec.services.count)
    }
}
