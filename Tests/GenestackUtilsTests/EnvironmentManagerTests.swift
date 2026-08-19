//
// EnvironmentManagerTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl

final class EnvironmentManagerTests: XCTestCase {
    
    func testGenerateEnvironmentWithDefaults() {
        let manager = EnvironmentManager(genestackDir: "/opt/genestack")
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
        
        let env = manager.generateEnvironment(spec: spec, overridesDir: "/etc/genestack")
        
        XCTAssertEqual(env["GENESTACK_BASE_DIR"], "/opt/genestack")
        XCTAssertEqual(env["GENESTACK_OVERRIDES_DIR"], "/etc/genestack")
        XCTAssertEqual(env["GENESTACK_SERVICES_DIR"], "/opt/genestack/bin/services")
        XCTAssertEqual(env["GENESTACK_COMPONENTS_FILE"], "/etc/genestack/openstack-components.yaml")
    }
    
    func testGenerateEnvironmentWithReplaceBase() {
        let manager = EnvironmentManager(genestackDir: "/opt/genestack")
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "test", gatewayDomain: nil, acmeEmail: nil),
            overrides: OverridesSpec(repo: "https://github.com/test/overrides", ref: "main", replaceBase: true),
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let env = manager.generateEnvironment(spec: spec, overridesDir: "/tmp/overrides")
        
        // When replaceBase is true, GENESTACK_BASE_DIR should be the overrides dir
        XCTAssertEqual(env["GENESTACK_BASE_DIR"], "/tmp/overrides")
        XCTAssertEqual(env["GENESTACK_OVERRIDES_DIR"], "/opt/genestack")
    }
    
    func testGenerateEnvironmentWithSpecVariables() {
        let manager = EnvironmentManager(genestackDir: "/opt/genestack")
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "test", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [],
            environment: [
                "ANSIBLE_FORKS": "24",
                "SKIP_PROMPTS": "true"
            ]
        )
        
        let env = manager.generateEnvironment(spec: spec, overridesDir: "/etc/genestack")
        
        XCTAssertEqual(env["ANSIBLE_FORKS"], "24")
        XCTAssertEqual(env["SKIP_PROMPTS"], "true")
        XCTAssertEqual(env["GENESTACK_BASE_DIR"], "/opt/genestack")
    }
    
    func testGenerateEnvironmentWithCustomGenestackDir() {
        let manager = EnvironmentManager(genestackDir: "/usr/local/genestack")
        
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
        
        let env = manager.generateEnvironment(spec: spec, overridesDir: "/etc/genestack")
        
        XCTAssertEqual(env["GENESTACK_BASE_DIR"], "/usr/local/genestack")
        XCTAssertEqual(env["GENESTACK_SERVICES_DIR"], "/usr/local/genestack/bin/services")
    }
    
    func testGetFullEnvironmentMergesWithProcessEnv() {
        let manager = EnvironmentManager(genestackDir: "/opt/genestack")
        
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "test", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [],
            environment: ["CUSTOM_VAR": "custom_value"]
        )
        
        let env = manager.getFullEnvironment(spec: spec, overridesDir: "/etc/genestack")
        
        // Should contain both process environment and spec environment
        XCTAssertNotNil(env["PATH"]) // From process environment
        XCTAssertEqual(env["CUSTOM_VAR"], "custom_value") // From spec
        XCTAssertEqual(env["GENESTACK_BASE_DIR"], "/opt/genestack")
    }
}
