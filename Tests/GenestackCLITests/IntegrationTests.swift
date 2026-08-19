//
// IntegrationTests.swift
// genestack-cli Tests
//
// Integration tests using realistic Genestack service YAML fixtures
//

import XCTest
@testable import genestackctl
import Foundation
import Yams

final class IntegrationTests: XCTestCase {
    
    /// Get the path to the test fixtures directory
    var fixturesPath: String {
        // Navigate from test file location to project root + Tests/Fixtures
        let currentFile = #file
        let components = currentFile.components(separatedBy: "/")
        
        // Find the "Tests" component and go up one level to project root
        if let testsIndex = components.firstIndex(of: "Tests") {
            let projectRoot = components[0..<testsIndex].joined(separator: "/")
            return projectRoot + "/Tests/Fixtures"
        }
        
        // Fallback to environment or current directory
        return FileManager.default.currentDirectoryPath + "/Tests/Fixtures"
    }
    
    /// Get path to services fixtures directory
    var servicesPath: String {
        return fixturesPath + "/services"
    }
    
    // MARK: - ServiceCatalog Integration Tests
    
    func testLoadRealServiceCatalog() throws {
        let catalog = try ServiceCatalog(path: servicesPath)
        let services = catalog.getAllServices()
        
        // All 5 services should be loaded (no template/common files)
        XCTAssertEqual(services.count, 5)
        
        // Verify expected services are present
        let names = services.map { $0.name }.sorted()
        XCTAssertEqual(names, ["cinder", "glance", "keystone", "neutron", "nova"])
    }
    
    func testCatalogParsesHelmChartObjects() throws {
        let catalog = try ServiceCatalog(path: servicesPath)
        
        let keystone = catalog.getService(named: "keystone")
        XCTAssertNotNil(keystone)
        XCTAssertEqual(keystone?.helmChart.repository, "https://github.com/openstack/openstack-helm")
        XCTAssertEqual(keystone?.helmChart.name, "keystone")
        XCTAssertEqual(keystone?.helmChart.version, "0.1.0")
    }
    
    func testCatalogParsesSecretsWithRotationFlags() throws {
        let catalog = try ServiceCatalog(path: servicesPath)
        
        let keystone = catalog.getService(named: "keystone")
        XCTAssertNotNil(keystone)
        XCTAssertNotNil(keystone?.secrets)
        
        // keystone should have 3 secrets
        XCTAssertEqual(keystone?.secrets?.count, 3)
        
        // Two should be rotatable
        let rotatable = catalog.getSecretsForRotation(service: "keystone")
        XCTAssertEqual(rotatable.count, 2)
    }
    
    func testCatalogParsesDependencies() throws {
        let catalog = try ServiceCatalog(path: servicesPath)
        
        let nova = catalog.getService(named: "nova")
        XCTAssertNotNil(nova)
        XCTAssertNotNil(nova?.dependencies)
        XCTAssertEqual(nova?.dependencies?.count, 2)
        XCTAssertEqual(nova?.dependencies?[0].name, "keystone")
    }
    
    // MARK: - Inventory Generator Integration Tests
    
    func testInventoryGenerationFromRealisticSpec() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(
                clusterName: "integration-test",
                gatewayDomain: "test.example.com",
                acmeEmail: "admin@test.example.com"
            ),
            overrides: OverridesSpec(
                repo: "https://github.com/example/overrides",
                ref: "main",
                replaceBase: false
            ),
            kubernetes: KubernetesSpec(
                hyperconverged: false,
                kubeVersion: "v1.35.6",
                groupVars: [
                    "openstack_control_plane": [
                        "enable_iscsi": "true"
                    ]
                ],
                vars: [
                    "cloud_name": "integration-test-1"
                ]
            ),
            nodes: [
                NodeSpec(
                    name: "controller01.test.example.com",
                    ip: "10.0.0.10",
                    roles: ["control-plane", "etcd", "kube-node", "openstack-control-plane"],
                    labels: ["zone": "us-west"],
                    taints: [],
                    addresses: [
                        "management_ip": "10.0.0.10",
                        "ansible_host": "172.28.0.10",
                        "network_mgmt_address": "172.28.0.10",
                        "network_storage_address": "172.28.1.10",
                        "network_overlay_address": "172.28.2.10"
                    ]
                ),
                NodeSpec(
                    name: "compute01.test.example.com",
                    ip: "10.0.0.11",
                    roles: ["kube-node", "openstack-compute-node"],
                    labels: nil,
                    taints: nil,
                    addresses: [
                        "management_ip": "10.0.0.11",
                        "ansible_host": "172.28.0.11",
                        "network_mgmt_address": "172.28.0.11",
                        "network_overlay_address": "172.28.2.11"
                    ]
                ),
                NodeSpec(
                    name: "block01.test.example.com",
                    ip: "10.0.1.10",
                    roles: ["kube-node", "openstack-storage-node"],
                    labels: nil,
                    taints: nil,
                    addresses: [
                        "management_ip": "10.0.1.10",
                        "ansible_host": "172.28.0.101",
                        "network_mgmt_address": "172.28.0.101",
                        "network_storage_address": "172.28.1.101"
                    ]
                )
            ],
            network: NetworkSpec(
                containerInterface: "bond0",
                containerVlanInterface: "bond0",
                computeInterface: "eth0",
                ovnExternalInterface: "bond0.126",
                ovnVlans: "bond0.126:bond0:126:1500",
                ovnExternalVlan: OVNExternalVlanSpec(
                    interface: "bond0.126",
                    parent: "bond0",
                    vlanId: 126,
                    mtu: 1500
                )
            ),
            storage: StorageSpec(longhornReplicas: 2, cinderBackend: "lvm"),
            services: [],
            environment: ["SKIP_PROMPTS": "true"]
        )
        
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // Verify comprehensive inventory structure
        XCTAssertTrue(inventory.contains("all:"))
        XCTAssertTrue(inventory.contains("vars:"))
        XCTAssertTrue(inventory.contains("cloud_name: \"integration-test-1\""))
        XCTAssertTrue(inventory.contains("hosts:"))
        XCTAssertTrue(inventory.contains("controller01.test.example.com"))
        XCTAssertTrue(inventory.contains("compute01.test.example.com"))
        XCTAssertTrue(inventory.contains("block01.test.example.com"))
        XCTAssertTrue(inventory.contains("children:"))
        XCTAssertTrue(inventory.contains("kube_control_plane:"))
        XCTAssertTrue(inventory.contains("etcd:"))
        XCTAssertTrue(inventory.contains("kube_node:"))
        XCTAssertTrue(inventory.contains("openstack_control_plane:"))
        XCTAssertTrue(inventory.contains("openstack_compute_nodes:"))
        XCTAssertTrue(inventory.contains("storage_nodes:"))
        XCTAssertTrue(inventory.contains("cinder_storage_nodes:"))
    }
    
    // MARK: - Dependency Resolution Integration Tests
    
    func testDependencyResolutionWithRealServices() throws {
        let catalog = try ServiceCatalog(path: servicesPath)
        let resolver = ServiceDependencyResolver(catalog: catalog)
        
        // All services except keystone should come after it
        let allServices = catalog.getAllServiceNames()
        let ordered = try resolver.resolveOrder(for: allServices)
        
        // keystone should be first
        XCTAssertEqual(ordered.first, "keystone")
        
        // cinder should come after both nova and keystone
        XCTAssertTrue(ordered.firstIndex(of: "keystone")! < ordered.firstIndex(of: "nova")!)
        XCTAssertTrue(ordered.firstIndex(of: "keystone")! < ordered.firstIndex(of: "cinder")!)
        XCTAssertTrue(ordered.firstIndex(of: "nova")! < ordered.firstIndex(of: "cinder")!)
    }
    
    // MARK: - Secret Analysis Integration Tests
    
    func testSecretAnalyzerWithRealServices() throws {
        let catalog = try ServiceCatalog(path: servicesPath)
        let analyzer = SecretAnalyzer(catalog: catalog)
        
        let ownershipMap = analyzer.analyzeOwnership()
        
        // Should find all rotatable secrets
        XCTAssertTrue(ownershipMap.secrets.count >= 8) // At least 8 secrets across 4 services
        
        // Test secret ownership
        let keystoneSecrets = ownershipMap.getSecrets(for: "keystone")
        XCTAssertNotNil(keystoneSecrets)
        XCTAssertEqual(keystoneSecrets?.count, 2)
        
        // Test rotation plan
        let plan = analyzer.planRotation(for: "keystone")
        XCTAssertEqual(plan.service, "keystone")
        XCTAssertEqual(plan.ownedSecrets.count, 2)
        XCTAssertTrue(plan.impactedServices.contains("glance"))
        XCTAssertTrue(plan.impactedServices.contains("nova"))
        XCTAssertTrue(plan.impactedServices.contains("neutron"))
        XCTAssertTrue(plan.impactedServices.contains("cinder"))
    }
    
    // MARK: - Full Pipeline Integration Test
    
    func testFullPipelineDryRun() throws {
        let catalog = try ServiceCatalog(path: servicesPath)
        
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(
                clusterName: "integration-test",
                gatewayDomain: "test.example.com",
                acmeEmail: "admin@test.example.com"
            ),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [
                ServiceSpec(name: "keystone", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "glance", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "nova", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "neutron", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "cinder", enabled: false, version: nil, helmArgs: nil)
            ],
            environment: nil
        )
        
        let executor = PipelineExecutor(
            genestackDir: servicesPath,
            catalog: catalog
        )
        
        let result = try executor.execute(
            spec: spec,
            dryRun: true
        )
        
        // Should succeed in dry run
        XCTAssertTrue(result.success)
        
        // Should include all enabled services (cinder is disabled)
        XCTAssertTrue(result.executedServices.contains("keystone"))
        XCTAssertTrue(result.executedServices.contains("glance"))
        XCTAssertTrue(result.executedServices.contains("nova"))
        XCTAssertTrue(result.executedServices.contains("neutron"))
        XCTAssertFalse(result.executedServices.contains("cinder"))
        
        // Keystone should be first (dependency for all others)
        XCTAssertEqual(result.executedServices.first, "keystone")
    }
    
    // MARK: - Environment Manager Integration Tests
    
    func testEnvironmentVariableGeneration() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(
                clusterName: "test",
                gatewayDomain: "test.local",
                acmeEmail: "admin@test.local"
            ),
            overrides: OverridesSpec(
                repo: "https://github.com/example/overrides",
                ref: "main",
                replaceBase: false
            ),
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [],
            environment: [
                "ANSIBLE_FORKS": "24",
                "CUSTOM_VAR": "test_value"
            ]
        )
        
        let manager = EnvironmentManager(genestackDir: nil)
        let env = manager.generateEnvironment(spec: spec, overridesDir: "/etc/genestack")
        
        // Verify all required environment variables are set
        XCTAssertEqual(env["GENESTACK_BASE_DIR"], "/opt/genestack")
        XCTAssertEqual(env["GENESTACK_OVERRIDES_DIR"], "/etc/genestack")
        XCTAssertEqual(env["GENESTACK_SERVICES_DIR"], "/opt/genestack/bin/services")
        XCTAssertEqual(env["GENESTACK_COMPONENTS_FILE"], "/etc/genestack/openstack-components.yaml")
        
        // Verify custom environment variables are passed through
        XCTAssertEqual(env["ANSIBLE_FORKS"], "24")
        XCTAssertEqual(env["CUSTOM_VAR"], "test_value")
    }
}
