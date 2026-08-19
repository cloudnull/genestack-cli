//
// ConfigCreateCommand.swift
// genestack-cli
//
// Creates a new cluster spec file with various generation options
//

import Foundation
import ArgumentParser
import Yams

/// Create a new cluster spec
struct ConfigCreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new cluster spec file"
    )
    
    @Option(help: "Output file path (default: genestack-cluster.yaml)")
    var output: String?
    
    @Option(help: "Path to Genestack installation (for service catalog discovery)")
    var genestackDir: String?
    
    @Flag(help: "Include all services from catalog as disabled")
    var allServices: Bool = false
    
    @Flag(help: "Include commonly used services enabled")
    var commonServices: Bool = false
    
    @Flag(help: "Skip confirmation prompt")
    var yes: Bool = false
    
    @Option(help: "Cluster name")
    var clusterName: String?
    
    @Option(help: "Gateway domain")
    var gatewayDomain: String?
    
    @Option(help: "ACME email")
    var acmeEmail: String?
    
    @Option(help: "Kubernetes version")
    var kubeVersion: String?
    
    @Flag(help: "Enable hyperconverged mode (auto-generates 3 nodes)")
    var hyperconverged: Bool = false
    
    func run() throws {
        let outputPath = output ?? "genestack-cluster.yaml"
        
        // Check for existing file
        if FileManager.default.fileExists(atPath: outputPath) && !yes {
            print("Error: File '\(outputPath)' already exists")
            print("Use --yes to overwrite, or choose a different --output path")
            throw ValidationError("File already exists")
        }
        
        // Get genestack directory
        let genestackPath = genestackDir ?? ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        let servicesPath = "\(genestackPath)/bin/services"
        
        // Determine cluster name
        let resolvedClusterName: String
        if let name = clusterName {
            resolvedClusterName = name
        } else {
            resolvedClusterName = ProcessInfo.processInfo.hostName
        }
        
        // Build the base spec
        var spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(
                clusterName: resolvedClusterName,
                gatewayDomain: gatewayDomain ?? "cluster.local",
                acmeEmail: acmeEmail ?? "admin@\(resolvedClusterName).local"
            ),
            overrides: nil,
            kubernetes: KubernetesSpec(
                hyperconverged: hyperconverged,
                kubeVersion: kubeVersion ?? "v1.35.6",
                groupVars: hyperconverged ? Self.hyperconvergedGroupVars : nil,
                vars: ["cloud_name": "\(resolvedClusterName)-1"]
            ),
            nodes: hyperconverged ? Self.createHyperconvergedNodes(clusterName: resolvedClusterName) : [],
            network: nil,
            storage: hyperconverged ? StorageSpec(longhornReplicas: 2, cinderBackend: "lvm") : nil,
            services: [],
            environment: ["SKIP_PROMPTS": "true"]
        )
        
        // Handle service inclusion based on flags
        if allServices || commonServices {
            spec.services = try createServiceList(
                servicesPath: servicesPath,
                commonServices: commonServices,
                allServices: allServices
            )
        }
        
        // Write the spec
        let yaml = try YAMLEncoder().encode(spec)
        try yaml.write(toFile: outputPath, atomically: true, encoding: String.Encoding.utf8)
        
        print("Cluster spec created: \(outputPath)")
        print("Cluster name: \(resolvedClusterName)")
        
        if hyperconverged {
            print("Mode: Hyperconverged (3 nodes auto-generated)")
        }
        
        if spec.services?.isEmpty == false {
            let enabledCount = spec.services?.filter { $0.enabled }.count ?? 0
            print("Services: \(enabledCount) enabled / \(spec.services?.count ?? 0) total")
        } else {
            print("Services: None specified (run 'genectl install' to configure)")
        }
        
        print("\nNext steps:")
        if spec.nodes?.isEmpty ?? true {
            print("  1. Edit the spec: genectl config edit --config \(outputPath)")
            print("  2. Add nodes manually or use: genectl install --config \(outputPath)")
        } else {
            print("  1. Review the spec: genectl config validate --config \(outputPath)")
        }
        print("  2. Apply when ready: genectl apply --config \(outputPath)")
    }
    
    // MARK: - Service List Creation
    
    /// Create service list based on flags
    private func createServiceList(
        servicesPath: String,
        commonServices: Bool,
        allServices: Bool
    ) throws -> [ServiceSpec] {
        // Try to load from catalog
        if FileManager.default.fileExists(atPath: servicesPath) {
            let catalog = try ServiceCatalog(path: servicesPath)
            let all = catalog.getAllServices()
            
            // Common services that are typically enabled
            let commonServiceNames: Set<String> = [
                "keystone",
                "glance", 
                "nova",
                "neutron",
                "cinder",
                "horizon",
                "placement"
            ]
            
            return all.map { service in
                let enabled: Bool
                if commonServices {
                    enabled = commonServiceNames.contains(service.name)
                } else {
                    // allServices mode - all disabled
                    enabled = false
                }
                return ServiceSpec(name: service.name, enabled: enabled, version: nil, helmArgs: nil)
            }.sorted { $0.name < $1.name }
        } else {
            // Fallback: no catalog available
            print("Warning: Service catalog not found at \(servicesPath)")
            print("Only basic services will be included")
            return []
        }
    }
    
    // MARK: - Hyperconverged Node Generation
    
    /// Create 3 hyperconverged nodes with appropriate roles
    private static func createHyperconvergedNodes(clusterName: String) -> [NodeSpec] {
        let roles = [
            "control-plane",
            "etcd",
            "kube-node",
            "openstack-control-plane",
            "openstack-compute-node",
            "openstack-network-node",
            "openstack-storage-node"
        ]
        
        return (1...3).map { i -> NodeSpec in
            let ip = "10.0.0.\(10 + i)"
            let ansibleHost = "172.28.0.\(10 + i)"
            
            return NodeSpec(
                name: "node0\(i).\(clusterName).local",
                ip: ip,
                roles: roles,
                labels: nil,
                taints: [],
                addresses: [
                    "management_ip": ip,
                    "ansible_host": ansibleHost,
                    "network_mgmt_address": ansibleHost,
                    "network_storage_address": "172.28.1.\(10 + i)",
                    "network_overlay_address": "172.28.2.\(10 + i)",
                    "network_storage_a_address": "172.28.3.\(10 + i)",
                    "network_storage_b_address": "172.28.4.\(10 + i)"
                ]
            )
        }
    }
    
    // MARK: - Hyperconverged Configuration
    
    /// Group variables for hyperconverged mode
    private static var hyperconvergedGroupVars: [String: [String: String]] {
        return [
            "openstack_control_plane": [
                "enable_iscsi": "true",
                "enable_nova": "true"
            ],
            "openstack_compute_nodes": [
                "enable_iscsi": "true",
                "custom_multipath": "true"
            ],
            "storage_nodes": [
                "enable_iscsi": "true",
                "storage_network_multipath": "true"
            ]
        ]
    }
}
