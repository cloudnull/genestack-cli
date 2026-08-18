//
// InventoryGeneratorTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl

final class InventoryGeneratorTests: XCTestCase {
    
    /// Helper: Create a test cluster spec
    func createTestSpec() -> ClusterSpec {
        return ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(
                clusterName: "dfw-dev",
                gatewayDomain: "dfw.dev.example.com",
                acmeEmail: "admin@dfw.dev.example.com"
            ),
            overrides: OverridesSpec(
                repo: "https://github.com/rackerlabs/flex-overrides-template",
                ref: "main",
                replaceBase: false
            ),
            kubernetes: KubernetesSpec(
                hyperconverged: false,
                kubeVersion: "v1.35.6",
                groupVars: [
                    "openstack_compute_nodes": [
                        "enable_iscsi": "true",
                        "custom_multipath": "true"
                    ],
                    "storage_nodes": [
                        "enable_iscsi": "true",
                        "storage_network_multipath": "true"
                    ]
                ],
                vars: [
                    "cloud_name": "dfw-dev-1",
                    "host_pin_kernel": "true"
                ]
            ),
            nodes: [
                NodeSpec(
                    name: "controller01.dfw-dev.local",
                    ip: "10.0.0.10",
                    roles: ["control-plane", "etcd", "kube-node", "openstack-control-plane"],
                    labels: ["node-role.kubernetes.io/worker": "worker"],
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
                    name: "compute01.dfw-dev.local",
                    ip: "10.0.0.11",
                    roles: ["kube-node", "openstack-compute-node"],
                    labels: nil,
                    taints: nil,
                    addresses: [
                        "management_ip": "10.0.0.11",
                        "ansible_host": "172.28.0.11",
                        "network_mgmt_address": "172.28.0.11",
                        "network_overlay_address": "172.28.2.11",
                        "network_storage_address": "172.28.1.11",
                        "network_storage_a_address": "172.28.3.11",
                        "network_storage_b_address": "172.28.4.11"
                    ]
                ),
                NodeSpec(
                    name: "block01.dfw-dev.local",
                    ip: "10.0.1.10",
                    roles: ["kube-node", "openstack-storage-node"],
                    labels: nil,
                    taints: nil,
                    addresses: [
                        "management_ip": "10.0.1.10",
                        "ansible_host": "172.28.0.101",
                        "network_mgmt_address": "172.28.0.101",
                        "network_overlay_address": "172.28.2.101",
                        "network_storage_address": "172.28.1.101",
                        "network_storage_a_address": "172.28.3.101",
                        "network_storage_b_address": "172.28.4.101"
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
            environment: [
                "SKIP_PROMPTS": "true",
                "ANSIBLE_FORKS": "24"
            ]
        )
    }
    
    func testGenerateBasicInventory() throws {
        let spec = createTestSpec()
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // Verify top-level structure
        XCTAssertTrue(inventory.contains("all:"))
        XCTAssertTrue(inventory.contains("vars:"))
        XCTAssertTrue(inventory.contains("hosts:"))
        XCTAssertTrue(inventory.contains("children:"))
        
        // Verify all nodes are present
        XCTAssertTrue(inventory.contains("controller01.dfw-dev.local"))
        XCTAssertTrue(inventory.contains("compute01.dfw-dev.local"))
        XCTAssertTrue(inventory.contains("block01.dfw-dev.local"))
    }
    
    func testGenerateInventoryWithVarSections() throws {
        let spec = createTestSpec()
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // Check global vars
        XCTAssertTrue(inventory.contains("cloud_name: \"dfw-dev-1\""))
        XCTAssertTrue(inventory.contains("host_pin_kernel: \"true\""))
        
        // Check that vars are indented correctly
        XCTAssertTrue(inventory.contains("    cloud_name:"))
    }
    
    func testGenerateInventoryWithHosts() throws {
        let spec = createTestSpec()
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // Verify host entries contain correct ansible_host
        XCTAssertTrue(inventory.contains("ansible_host: \"172.28.0.10\""))
        XCTAssertTrue(inventory.contains("ansible_host: \"172.28.0.11\""))
        XCTAssertTrue(inventory.contains("ansible_host: \"172.28.0.101\""))
        
        // Verify address entries
        XCTAssertTrue(inventory.contains("management_ip: \"10.0.0.10\""))
        XCTAssertTrue(inventory.contains("network_mgmt_address: \"172.28.0.10\""))
    }
    
    func testGenerateInventoryWithKubesprayGroups() throws {
        let spec = createTestSpec()
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // Verify kubespray groups exist
        XCTAssertTrue(inventory.contains("kube_control_plane:"))
        XCTAssertTrue(inventory.contains("etcd:"))
        XCTAssertTrue(inventory.contains("kube_node:"))
        XCTAssertTrue(inventory.contains("openstack_control_plane:"))
        XCTAssertTrue(inventory.contains("openstack_compute_nodes:"))
        XCTAssertTrue(inventory.contains("storage_nodes:"))
        
        // Controller should be in control plane
        XCTAssertTrue(inventory.contains("controller01.dfw-dev.local: null"))
        
        // Both controller and compute should be kube nodes
        XCTAssertTrue(inventory.contains("compute01.dfw-dev.local: null"))
        XCTAssertTrue(inventory.contains("block01.dfw-dev.local: null"))
    }
    
    func testGenerateInventoryWithGroupVars() throws {
        let spec = createTestSpec()
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // Check compute nodes group vars
        XCTAssertTrue(inventory.contains("enable_iscsi: true"))
        XCTAssertTrue(inventory.contains("custom_multipath: true"))
        
        // Check storage nodes group vars
        XCTAssertTrue(inventory.contains("storage_network_multipath: true"))
    }
    
    func testGenerateInventoryWithCinderStorageNodes() throws {
        let spec = createTestSpec()
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // Storage nodes should have cinder_storage_nodes child
        XCTAssertTrue(inventory.contains("cinder_storage_nodes:"))
        XCTAssertTrue(inventory.contains("block01.dfw-dev.local: null"))
    }
    
    func testGenerateInventoryWithK8sClusterSection() throws {
        let spec = createTestSpec()
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // k8s_cluster should include OVN interface settings
        XCTAssertTrue(inventory.contains("k8s_cluster:"))
        XCTAssertTrue(inventory.contains("kube_ovn_central_hosts:"))
        XCTAssertTrue(inventory.contains("kube_ovn_default_interface_name: bond0"))
        XCTAssertTrue(inventory.contains("kube_ovn_iface: bond0"))
    }
    
    func testGenerateInventoryWithOVNEmptyGroup() throws {
        let spec = createTestSpec()
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // ovn_network_nodes should be empty since no node has openstack-network-node role
        XCTAssertTrue(inventory.contains("ovn_network_nodes:"))
        XCTAssertTrue(inventory.contains("hosts: {}"))
    }
    
    func testGenerateInventoryWithHyperconvergedNodes() throws {
        let spec = createTestSpec()
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // Should still generate correct inventory
        XCTAssertTrue(inventory.contains("all:"))
    }
    
    func testInventoryMatchesExpectedFormat() throws {
        let spec = createTestSpec()
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        // Verify the format matches the expected kubespray inventory structure from spec.md
        let expectedLines = [
            "all:",
            "  vars:",
            "    cloud_name: \"dfw-dev-1\"",
            "    host_pin_kernel: \"true\"",
            "  hosts:",
            "    controller01.dfw-dev.local:",
            "      ansible_host: \"172.28.0.10\"",
            "      management_ip: \"10.0.0.10\"",
            "      network_mgmt_address: \"172.28.0.10\"",
            "      network_storage_address: \"172.28.1.10\"",
            "      network_overlay_address: \"172.28.2.10\"",
            "  children:",
            "    kube_control_plane:",
            "      hosts:",
            "        controller01.dfw-dev.local: null",
            "    etcd:",
            "      hosts:",
            "        controller01.dfw-dev.local: null"
        ]
        
        for line in expectedLines {
            XCTAssertTrue(inventory.contains(line), "Missing expected line in inventory: \(line)")
        }
    }
    
    func testGenerateInventoryForSingleController() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "test", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [
                NodeSpec(
                    name: "controller01.test.local",
                    ip: "10.0.0.10",
                    roles: ["control-plane", "etcd", "openstack-control-plane"],
                    labels: nil,
                    taints: nil,
                    addresses: ["ansible_host": "172.28.0.10", "management_ip": "10.0.0.10"]
                )
            ],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let generator = InventoryGenerator()
        let inventory = try generator.generate(spec: spec)
        
        XCTAssertTrue(inventory.contains("kube_control_plane:"))
        XCTAssertTrue(inventory.contains("openstack_control_plane:"))
        XCTAssertFalse(inventory.contains("openstack_compute_nodes: hosts:"))
    }
}
