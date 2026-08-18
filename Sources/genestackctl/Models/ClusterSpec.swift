//
// ClusterSpec.swift
// genestack-cli
//
// Created for the genestack-cli Swift implementation
//

import Foundation
import Yams

// MARK: - Top-Level Spec

struct ClusterSpec: Codable, Equatable {
    var version: String
    var metadata: MetadataSpec
    var overrides: OverridesSpec?
    var kubernetes: KubernetesSpec?
    var nodes: [NodeSpec]
    var network: NetworkSpec?
    var storage: StorageSpec?
    var services: [ServiceSpec]
    var environment: [String: String]?
}

// MARK: - Metadata

struct MetadataSpec: Codable, Equatable {
    let clusterName: String
    let gatewayDomain: String?
    let acmeEmail: String?
    
    enum CodingKeys: String, CodingKey {
        case clusterName = "cluster_name"
        case gatewayDomain = "gateway_domain"
        case acmeEmail = "acme_email"
    }
}

// MARK: - Overrides

struct OverridesSpec: Codable, Equatable {
    let repo: String?
    let ref: String?
    let replaceBase: Bool?
    
    enum CodingKeys: String, CodingKey {
        case repo, ref, replaceBase = "replace_base"
    }
}

// MARK: - Kubernetes

struct KubernetesSpec: Codable, Equatable {
    let hyperconverged: Bool?
    let kubeVersion: String?
    let groupVars: [String: [String: String]]?
    let vars: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case hyperconverged
        case kubeVersion = "kube_version"
        case groupVars = "group_vars"
        case vars
    }
}

// MARK: - Node

struct NodeSpec: Codable, Equatable {
    let name: String
    let ip: String
    let roles: [String]
    let labels: [String: String]?
    let taints: [String]?
    let addresses: [String: String]?
}

// MARK: - Network

struct NetworkSpec: Codable, Equatable {
    let containerInterface: String?
    let containerVlanInterface: String?
    let computeInterface: String?
    let ovnExternalInterface: String?
    let ovnVlans: String?
    let ovnExternalVlan: OVNExternalVlanSpec?
    
    enum CodingKeys: String, CodingKey {
        case containerInterface = "container_interface"
        case containerVlanInterface = "container_vlan_interface"
        case computeInterface = "compute_interface"
        case ovnExternalInterface = "ovn_external_interface"
        case ovnVlans = "ovn_vlans"
        case ovnExternalVlan = "ovn_external_vlan"
    }
}

struct OVNExternalVlanSpec: Codable, Equatable {
    let interface: String?
    let parent: String?
    let vlanId: Int?
    let mtu: Int?
    
    enum CodingKeys: String, CodingKey {
        case interface, parent, vlanId = "vlan_id", mtu
    }
}

// MARK: - Storage

struct StorageSpec: Codable, Equatable {
    let longhornReplicas: Int?
    let cinderBackend: String?
    
    enum CodingKeys: String, CodingKey {
        case longhornReplicas = "longhorn_replicas"
        case cinderBackend = "cinder_backend"
    }
}

// MARK: - Service

struct ServiceSpec: Codable, Equatable {
    let name: String
    let enabled: Bool
    let version: String?
    let helmArgs: [String]?
    
    enum CodingKeys: String, CodingKey {
        case name, enabled, version, helmArgs = "helm_args"
    }
}

// MARK: - Spec Loading/Serialization

extension ClusterSpec {
    static func load(from path: String) throws -> ClusterSpec {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let yaml = try Yams.load(yaml: content)
        guard let dict = yaml as? [String: Any] else {
            throw NSError(domain: "ClusterSpec", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid YAML structure"])
        }
        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
        return try JSONDecoder().decode(ClusterSpec.self, from: jsonData)
    }
    
    func save(to path: String, prettyPrint: Bool = true) throws {
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(self)
        try yaml.write(toFile: path, atomically: true, encoding: String.Encoding.utf8)
    }
}
