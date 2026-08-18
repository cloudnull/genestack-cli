//
// SpecValidatorTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl

final class SpecValidatorTests: XCTestCase {
    func testValidateValidSpec() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "mycloud", gatewayDomain: "cluster.local", acmeEmail: "admin@example.com"),
            overrides: nil,
            kubernetes: nil,
            nodes: [
                NodeSpec(name: "node01", ip: "10.0.0.10", roles: ["control-plane"], labels: nil, taints: nil, addresses: nil)
            ],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let validator = SpecValidator()
        let result = validator.validate(spec: spec)
        
        XCTAssertTrue(result.isValid, "Valid spec should pass validation")
        XCTAssertTrue(result.errors.isEmpty, "Valid spec should have no errors")
    }
    
    func testRejectInvalidVersion() throws {
        let spec = ClusterSpec(
            version: "2.0",
            metadata: MetadataSpec(clusterName: "mycloud", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let validator = SpecValidator()
        let result = validator.validate(spec: spec)
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("Unsupported spec version") })
    }
    
    func testRejectEmptyClusterName() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let validator = SpecValidator()
        let result = validator.validate(spec: spec)
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("cluster_name is required") })
    }
    
    func testRejectDuplicateNodeNames() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "mycloud", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [
                NodeSpec(name: "node01", ip: "10.0.0.10", roles: ["control-plane"], labels: nil, taints: nil, addresses: nil),
                NodeSpec(name: "node01", ip: "10.0.0.11", roles: ["worker"], labels: nil, taints: nil, addresses: nil)
            ],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let validator = SpecValidator()
        let result = validator.validate(spec: spec)
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("Duplicate node name") })
    }
    
    func testRejectDuplicateNodeIPs() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "mycloud", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [
                NodeSpec(name: "node01", ip: "10.0.0.10", roles: ["control-plane"], labels: nil, taints: nil, addresses: nil),
                NodeSpec(name: "node02", ip: "10.0.0.10", roles: ["worker"], labels: nil, taints: nil, addresses: nil)
            ],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let validator = SpecValidator()
        let result = validator.validate(spec: spec)
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("Duplicate node IP") })
    }
    
    func testRejectInvalidIP() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "mycloud", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [
                NodeSpec(name: "node01", ip: "999.999.999.999", roles: ["control-plane"], labels: nil, taints: nil, addresses: nil)
            ],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let validator = SpecValidator()
        let result = validator.validate(spec: spec)
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("invalid IP address") })
    }
    
    func testRejectNodeWithoutRoles() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "mycloud", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [
                NodeSpec(name: "node01", ip: "10.0.0.10", roles: [], labels: nil, taints: nil, addresses: nil)
            ],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let validator = SpecValidator()
        let result = validator.validate(spec: spec)
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("must have at least one role") })
    }
    
    func testRejectDuplicateServices() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "mycloud", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [
                ServiceSpec(name: "keystone", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "keystone", enabled: false, version: nil, helmArgs: nil)
            ],
            environment: nil
        )
        
        let validator = SpecValidator()
        let result = validator.validate(spec: spec)
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("Duplicate service name") })
    }
    
    func testValidateWithOverridesRepo() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "mycloud", gatewayDomain: nil, acmeEmail: nil),
            overrides: OverridesSpec(repo: "https://github.com/example/overrides", ref: "main", replaceBase: nil),
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let validator = SpecValidator()
        let result = validator.validate(spec: spec)
        
        XCTAssertTrue(result.isValid)
    }
    
    func testRejectInvalidOverridesRepoURL() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "mycloud", gatewayDomain: nil, acmeEmail: nil),
            overrides: OverridesSpec(repo: "not-a-url", ref: "main", replaceBase: nil),
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let validator = SpecValidator()
        let result = validator.validate(spec: spec)
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("overrides.repo must be a valid URL") })
    }
}
