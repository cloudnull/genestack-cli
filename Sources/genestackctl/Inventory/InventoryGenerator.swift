//
// InventoryGenerator.swift
// genestack-cli
//
// Generates Ansible inventory (inventory.yaml) from the cluster spec
//

import Foundation
import Yams

/// Role-to-kubespray-group mapping
/// Maps genestack roles to kubespray groups
private let roleToKubesprayGroups: [String: [String]] = [
    "control-plane": ["kube_control_plane", "kube_node"],
    "etcd": ["etcd"],
    "kube-node": ["kube_node"],
    "openstack-control-plane": ["openstack_control_plane"],
    "openstack-compute-node": ["openstack_compute_nodes"],
    "openstack-network-node": ["ovn_network_nodes"],
    "openstack-storage-node": ["storage_nodes"]
]

/// Role-to-group-variable mapping for group_vars sections
private let roleToGroupVars: [String: String] = [
    "openstack-control-plane": "openstack_control_plane",
    "openstack-compute-node": "openstack_compute_nodes",
    "openstack-network-node": "ovn_network_nodes",
    "openstack-storage-node": "storage_nodes"
]

/// Generates kubespray-format Ansible inventory from a ClusterSpec
class InventoryGenerator {
    
    /// Generate Ansible inventory YAML from cluster spec
    /// - Parameter spec: Cluster specification
    /// - Returns: YAML string of the generated inventory
    func generate(spec: ClusterSpec) throws -> String {
        // Build hosts dictionary
        var hosts: [String: [String: String]] = [:]
        
        for node in spec.nodes ?? [] {
            let addresses = node.addresses ?? [:]
            var hostVars: [String: String] = [:]
            
            // Extract ansible_host (required)
            let ansibleHost = addresses["ansible_host"] ?? node.ip
            hostVars["ansible_host"] = ansibleHost
            
            // Extract management IP
            if let managementIP = addresses["management_ip"] {
                hostVars["management_ip"] = managementIP
            }
            
            // Extract network addresses
            let addressKeys = [
                "network_mgmt_address",
                "network_storage_address", 
                "network_overlay_address",
                "network_storage_a_address",
                "network_storage_b_address"
            ]
            
            for key in addressKeys {
                if let value = addresses[key] {
                    hostVars[key] = value
                }
            }
            
            hosts[node.name] = hostVars
        }
        
        // Build groups
        var groups: [String: Set<String>] = [:]
        
        for node in spec.nodes ?? [] {
            for role in node.roles {
                if let k8sGroups = roleToKubesprayGroups[role] {
                    for group in k8sGroups {
                        groups[group, default: Set()].insert(node.name)
                    }
                }
            }
        }
        
        // Generate YAML output
        var yamlLines: [String] = []
        yamlLines.append("all:")
        
        // Vars section (global vars)
        if let kubernetesVars = spec.kubernetes?.vars, !kubernetesVars.isEmpty {
            yamlLines.append("  vars:")
            for (key, value) in kubernetesVars.sorted(by: { $0.key < $1.key }) {
                yamlLines.append("    \(safeYAML(key)): \"\(safeYAML(value))\"")
            }
        }
        
        // Hosts section
        yamlLines.append("  hosts:")
        for (name, hostVars) in hosts.sorted(by: { $0.key < $1.key }) {
            yamlLines.append("    \(name):")
            for (key, value) in hostVars.sorted(by: { $0.key < $1.key }) {
                yamlLines.append("      \(key): \"\(safeYAML(value))\"")
            }
        }
        
        // Children section
        yamlLines.append("  children:")
        
        // Define all kubespray groups with proper ordering
        let orderedGroups = [
            "kube_control_plane",
            "etcd",
            "kube_node",
            "openstack_control_plane",
            "openstack_compute_nodes",
            "ovn_network_nodes",
            "storage_nodes"
        ]
        
        for group in orderedGroups {
            guard let nodesInGroup = groups[group], !nodesInGroup.isEmpty else {
                // Still emit empty group if it's referenced elsewhere
                if group == "ovn_network_nodes" {
                    yamlLines.append("    \(group):")
                    yamlLines.append("      hosts: {}")
                }
                continue
            }
            
            yamlLines.append("    \(group):")
            
            // Add group vars if present
            if let groupVars = spec.kubernetes?.groupVars?[group] {
                yamlLines.append("      vars:")
                for (key, value) in groupVars.sorted(by: { $0.key < $1.key }) {
                    yamlLines.append("        \(safeYAML(key)): \(safeYAML(value))")
                }
            }
            
            // Add hosts
            yamlLines.append("      hosts:")
            for node in nodesInGroup.sorted() {
                yamlLines.append("        \(node): null")
            }
            
            // Handle cinder_storage_nodes child for storage_nodes
            if group == "storage_nodes" {
                yamlLines.append("      children:")
                yamlLines.append("        cinder_storage_nodes:")
                yamlLines.append("          hosts:")
                for node in nodesInGroup.sorted() {
                    yamlLines.append("            \(node): null")
                }
            }
        }
        
        // Handle k8s_cluster children with network config
        yamlLines.append("    k8s_cluster:")
        if let kubeOvnInterface = spec.network?.containerInterface {
            yamlLines.append("      vars:")
            yamlLines.append("        kube_ovn_central_hosts: '{{ groups[\"ovn_network_nodes\"] }}'")
            yamlLines.append("        kube_ovn_default_interface_name: \(kubeOvnInterface)")
            yamlLines.append("        kube_ovn_iface: \(spec.network?.containerInterface ?? "bond0")")
        }
        
        return yamlLines.joined(separator: "\n")
    }
    
    /// Escape strings for safe YAML embedding
    private func safeYAML(_ input: String) -> String {
        // Escape special characters that have meaning in YAML
        return input
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
    }
}
