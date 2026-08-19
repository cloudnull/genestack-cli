//
// Wizard.swift
// genestack-cli
//
// Interactive wizard for cluster configuration
//

import Foundation
import Yams

/// Interactive wizard for building a ClusterSpec
class Wizard {
    private let config: String?
    private var spec: ClusterSpec
    
    init(config: String?) {
        self.config = config
        // Try to load existing spec for pre-filling
        if let configPath = config, FileManager.default.fileExists(atPath: configPath) {
            do {
                let content = try String(contentsOfFile: configPath)
                self.spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
            } catch {
                self.spec = Wizard.createDefaultSpec()
            }
        } else {
            self.spec = Wizard.createDefaultSpec()
        }
    }
    
    /// Create a default cluster spec with sensible defaults
    static func createDefaultSpec() -> ClusterSpec {
        let hostname = ProcessInfo.processInfo.hostName
        return ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(
                clusterName: hostname,
                gatewayDomain: "cluster.local",
                acmeEmail: "admin@\(hostname)"
            ),
            overrides: nil,
            kubernetes: KubernetesSpec(
                hyperconverged: false,
                kubeVersion: "v1.35.6",
                groupVars: nil,
                vars: ["cloud_name": "\(hostname)-1"]
            ),
            nodes: [],
            network: nil,
            storage: StorageSpec(longhornReplicas: 2, cinderBackend: "lvm"),
            services: [],
            environment: ["SKIP_PROMPTS": "true"]
        )
    }
    
    /// Run the interactive wizard
    /// - Parameter assumeDefaults: If true, skip all prompts and use defaults
    /// - Returns: Completed cluster spec
    func run(assumeDefaults: Bool = false) throws -> ClusterSpec {
        print("=== Genestack Cluster Installation Wizard ===\n")
        
        // Step 1: Cluster basics
        print("Step 1: Cluster Basics")
        if assumeDefaults {
            print("  (Using defaults due to --yes flag)")
        } else {
            spec.metadata = promptClusterBasics(metadata: spec.metadata)
        }
        print("")
        
        // Step 2: Overrides repo
        print("Step 2: Overrides Repository")
        if assumeDefaults {
            print("  (Using defaults due to --yes flag)")
        } else {
            spec.overrides = promptOverrides(overrides: spec.overrides)
        }
        print("")
        
        // Step 3: Node inventory
        print("Step 3: Node Inventory")
        if assumeDefaults {
            print("  (Using defaults due to --yes flag)")
        } else {
            spec.nodes = try promptNodes(nodes: spec.nodes ?? [])
        }
        print("")
        
        // Step 4: Network configuration
        print("Step 4: Network Configuration")
        if assumeDefaults {
            print("  (Using defaults due to --yes flag)")
        } else {
            spec.network = promptNetwork(network: spec.network)
        }
        print("")
        
        // Step 5: Storage configuration
        print("Step 5: Storage Configuration")
        if assumeDefaults {
            print("  (Using defaults due to --yes flag)")
        } else {
            spec.storage = promptStorage(storage: spec.storage)
        }
        print("")
        
        // Step 6: Service selection
        print("Step 6: Service Selection")
        if assumeDefaults {
            print("  (Using defaults due to --yes flag)")
        } else {
            try promptServices()
        }
        print("")
        
        // Step 7: Advanced settings
        print("Step 7: Advanced Settings")
        if assumeDefaults {
            print("  (Using defaults due to --yes flag)")
        } else {
            promptAdvancedSettings()
        }
        print("")
        
        // Step 8: Review
        print("Step 8: Review & Confirm")
        print(reviewSummary())
        
        if !assumeDefaults {
            print("\nProceed with installation? (y/N): ", terminator: "")
            let response = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) ?? "n"
            if response != "y" {
                print("Installation cancelled.")
                throw CancellationError()
            }
        }
        
        return spec
    }
    
    // MARK: - Prompt Methods
    
    private func promptClusterBasics(metadata: MetadataSpec) -> MetadataSpec {
        let clusterName = prompt("Cluster name", defaultValue: metadata.clusterName)
        let gatewayDomain = prompt("Gateway domain", defaultValue: metadata.gatewayDomain ?? "cluster.local")
        let acmeEmail = prompt("ACME email", defaultValue: metadata.acmeEmail ?? "admin@\(metadata.clusterName).local")
        
        return MetadataSpec(clusterName: clusterName, gatewayDomain: gatewayDomain, acmeEmail: acmeEmail)
    }
    
    private func promptOverrides(overrides: OverridesSpec?) -> OverridesSpec? {
        let repo = prompt("Overrides repo URL (empty for none)", defaultValue: overrides?.repo ?? "")
        
        if repo.isEmpty {
            return overrides
        }
        
        let ref = prompt("Git ref (branch/tag)", defaultValue: overrides?.ref ?? "main")
        let replaceBaseInput = prompt("Replace base dir? (y/N)", defaultValue: overrides?.replaceBase == true ? "y" : "n")
        let replaceBase = replaceBaseInput.lowercased() == "y"
        
        return OverridesSpec(repo: repo, ref: ref, replaceBase: replaceBase)
    }
    
    private func promptNodes(nodes: [NodeSpec]) throws -> [NodeSpec] {
        print("Current nodes: \(nodes.count) defined")
        
        // Check if hyperconverged mode
        let hyperconverged = spec.kubernetes?.hyperconverged ?? false
        if hyperconverged {
            print("Hyperconverged mode is enabled.")
            print("Auto-generating 3 nodes with all roles...")
            
            return createHyperconvergedNodes()
        }
        
        var result: [NodeSpec] = nodes
        var continueAdding = true
        
        while continueAdding {
            let name = prompt("Node name", defaultValue: "")
            let ip = prompt("Node IP", defaultValue: "")
            let roleString = prompt("Roles (comma-separated)", defaultValue: "control-plane,etcd,kube-node,openstack-control-plane")
            let roles = roleString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            let node = NodeSpec(
                name: name,
                ip: ip,
                roles: roles,
                labels: nil,
                taints: nil,
                addresses: [
                    "management_ip": ip,
                    "ansible_host": ip,
                    "network_mgmt_address": ip,
                    "network_storage_address": ip,
                    "network_overlay_address": ip
                ]
            )
            
            result.append(node)
            
            let addAnother = prompt("Add another node? (Y/n)", defaultValue: "y")
            continueAdding = addAnother.lowercased() != "n"
        }
        
        return result
    }
    
    private func createHyperconvergedNodes() -> [NodeSpec] {
        let clusterName = spec.metadata.clusterName
        var nodes: [NodeSpec] = []
        
        let roles = ["control-plane", "etcd", "kube-node", "openstack-control-plane", "openstack-compute-node", "openstack-storage-node"]
        
        for i in 1...3 {
            let nodeName = "node0\(i).\(clusterName).local"
            let nodeIP = prompt("Node \(i) IP", defaultValue: "10.0.0.\(10 + i)")
            
            let node = NodeSpec(
                name: nodeName,
                ip: nodeIP,
                roles: roles,
                labels: nil,
                taints: nil,
                addresses: [
                    "management_ip": nodeIP,
                    "ansible_host": "172.28.0.\(10 + i)",
                    "network_mgmt_address": "172.28.0.\(10 + i)",
                    "network_storage_address": "172.28.1.\(10 + i)",
                    "network_overlay_address": "172.28.2.\(10 + i)"
                ]
            )
            
            nodes.append(node)
        }
        
        return nodes
    }
    
    private func promptNetwork(network: NetworkSpec?) -> NetworkSpec {
        let defaults = network ?? NetworkSpec(
            containerInterface: nil,
            containerVlanInterface: nil,
            computeInterface: nil,
            ovnExternalInterface: nil,
            ovnVlans: nil,
            ovnExternalVlan: nil
        )
        
        let containerInterface = prompt("Container interface", defaultValue: defaults.containerInterface ?? "bond0")
        let computeInterface = prompt("Compute interface", defaultValue: defaults.computeInterface ?? "eth0")
        let ovnExternalInterface = prompt("OVN external interface", defaultValue: defaults.ovnExternalInterface ?? "bond0.126")
        
        print("OVN external VLAN settings:")
        let vlanInterface = prompt("VLAN interface", defaultValue: defaults.ovnExternalVlan?.interface ?? "bond0.126")
        let vlanParent = prompt("VLAN parent", defaultValue: defaults.ovnExternalVlan?.parent ?? "bond0")
        let vlanIdStr = prompt("VLAN ID", defaultValue: defaults.ovnExternalVlan?.vlanId?.description ?? "126")
        let vlanMTU = prompt("VLAN MTU", defaultValue: defaults.ovnExternalVlan?.mtu?.description ?? "1500")
        
        return NetworkSpec(
            containerInterface: containerInterface,
            containerVlanInterface: containerInterface,
            computeInterface: computeInterface,
            ovnExternalInterface: ovnExternalInterface,
            ovnVlans: "\(vlanInterface):\(vlanParent):\(vlanIdStr):\(vlanMTU)",
            ovnExternalVlan: OVNExternalVlanSpec(
                interface: vlanInterface,
                parent: vlanParent,
                vlanId: Int(vlanIdStr),
                mtu: Int(vlanMTU)
            )
        )
    }
    
    private func promptStorage(storage: StorageSpec?) -> StorageSpec {
        let defaults = storage ?? StorageSpec(longhornReplicas: 2, cinderBackend: "lvm")
        
        let replicasStr = prompt("Longhorn replicas", defaultValue: defaults.longhornReplicas?.description ?? "2")
        let cinderBackend = prompt("Cinder backend (lvm/netapp-iscsi/ceph)", defaultValue: defaults.cinderBackend ?? "lvm")
        
        return StorageSpec(
            longhornReplicas: Int(replicasStr),
            cinderBackend: cinderBackend
        )
    }
    
    private func promptServices() throws {
        let genestackDir = ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        let servicesPath = "\(genestackDir)/bin/services"
        
        guard FileManager.default.fileExists(atPath: servicesPath) else {
            print("Warning: Service catalog not found at \(servicesPath)")
            print("All 50+ services will be listed as disabled in the spec.")
            return
        }
        
        do {
            let catalog = try ServiceCatalog(path: servicesPath)
            let allServices = catalog.getAllServices()
            
            print("Available services (50+ total). Toggle services to enable:")
            print("(Currently showing first 20. Edit genestack-cluster.yaml manually to add more)")
            
            // For the wizard, we'll enable keystone by default (required)
            var servicesInSpec: [ServiceSpec] = []
            
            for service in allServices.prefix(20) {
                let currentlyEnabled = spec.services?.contains { $0.name == service.name && $0.enabled } ?? false
                let promptMsg = "Enable \(service.name)? [y/N/auto]"
                let response = prompt(promptMsg, defaultValue: currentlyEnabled ? "y" : "n")
                
                if response.lowercased() == "y" || response.lowercased() == "yes" {
                    servicesInSpec.append(ServiceSpec(name: service.name, enabled: true, version: nil, helmArgs: nil))
                } else if response.lowercased() == "auto" {
                    servicesInSpec.append(ServiceSpec(name: service.name, enabled: true, version: nil, helmArgs: nil))
                } else {
                    servicesInSpec.append(ServiceSpec(name: service.name, enabled: false, version: nil, helmArgs: nil))
                }
            }
            
            // Add remaining services as disabled
            for service in allServices.dropFirst(20) {
                servicesInSpec.append(ServiceSpec(name: service.name, enabled: false, version: nil, helmArgs: nil))
            }
            
            spec = ClusterSpec(
                version: spec.version,
                metadata: spec.metadata,
                overrides: spec.overrides,
                kubernetes: spec.kubernetes,
                nodes: spec.nodes ?? [],
                network: spec.network,
                storage: spec.storage,
                services: servicesInSpec,
                environment: spec.environment
            )
        } catch {
            print("Warning: Could not load service catalog: \(error)")
        }
    }
    
    private func promptAdvancedSettings() {
        let hyperconvergedInput = prompt("Hyperconverged mode? (y/N)", defaultValue: spec.kubernetes?.hyperconverged == true ? "y" : "n")
        let hyperconverged = hyperconvergedInput.lowercased() == "y"
        
        let kubeVersion = prompt("Kubernetes version", defaultValue: spec.kubernetes?.kubeVersion ?? "v1.35.6")
        
        if var k8s = spec.kubernetes {
            k8s = KubernetesSpec(
                hyperconverged: hyperconverged,
                kubeVersion: kubeVersion,
                groupVars: k8s.groupVars,
                vars: k8s.vars
            )
            spec = ClusterSpec(
                version: spec.version,
                metadata: spec.metadata,
                overrides: spec.overrides,
                kubernetes: k8s,
                nodes: spec.nodes ?? [],
                network: spec.network,
                storage: spec.storage,
                services: spec.services ?? [],
                environment: spec.environment
            )
        }
    }
    
    // MARK: - Utility Methods
    
    private func prompt(_ message: String, defaultValue: String) -> String {
        let promptText = "\(message) [\(defaultValue)]: "
        print(promptText, terminator: "")
        
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            return input
        }
        return defaultValue
    }
    
    private func reviewSummary() -> String {
        var summary = "Cluster Configuration Summary:\n"
        summary += "==============================\n"
        summary += "  Name: \(spec.metadata.clusterName)\n"
        summary += "  Gateway: \(spec.metadata.gatewayDomain ?? "N/A")\n"
        summary += "  ACME Email: \(spec.metadata.acmeEmail ?? "N/A")\n"
        summary += "  Nodes: \(spec.nodes?.count ?? 0)\n"
        summary += "  Services: \(spec.services?.filter { $0.enabled }.count ?? 0) enabled / \(spec.services?.count ?? 0) total\n"
        summary += "  Overrides: \(spec.overrides?.repo ?? "none")\n"
        summary += "  Hyperconverged: \(spec.kubernetes?.hyperconverged == true ? "yes" : "no")\n"
        return summary
    }
}
