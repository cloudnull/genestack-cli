//
// InventoryModel.swift
// genestack-cli
//
// Data structures for the Ansible/kubespray inventory
//

import Foundation

/// Represents a host entry in the Ansible inventory
struct AnsibleHostEntry: Codable, Equatable {
    let ansibleHost: String
    let managementIP: String?
    let networkMgmtAddress: String?
    let networkStorageAddress: String?
    let networkOverlayAddress: String?
    let networkStorageAAddress: String?
    let networkStorageBAddress: String?
    
    enum CodingKeys: String, CodingKey {
        case ansibleHost = "ansible_host"
        case managementIP = "management_ip"
        case networkMgmtAddress = "network_mgmt_address"
        case networkStorageAddress = "network_storage_address"
        case networkOverlayAddress = "network_overlay_address"
        case networkStorageAAddress = "network_storage_a_address"
        case networkStorageBAddress = "network_storage_b_address"
    }
}

/// Represents a group in the kubespray inventory (kube_control_plane, etcd, etc.)
struct AnsibleGroupSection: Codable, Equatable {
    let vars: [String: String]?
    let hosts: [String: AnsibleHostEntry]?
    let children: [String: AnsibleGroupSection]?
}
