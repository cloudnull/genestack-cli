//
// NodeCommands.swift
// genestack-cli
//
// CLI commands for managing nodes: list, add, remove
//

import Foundation
import ArgumentParser
import Yams

/// Parent command for node management
struct NodeCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "node",
        abstract: "Manage cluster nodes",
        subcommands: [NodeListCommand.self, NodeAddCommand.self, NodeRemoveCommand.self]
    )
}

/// List all nodes in the cluster spec
struct NodeListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all nodes in cluster spec"
    )
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    func run() throws {
        let configPath = config ?? "genestack-cluster.yaml"
        
        guard FileManager.default.fileExists(atPath: configPath) else {
            print("Error: Config file '\(configPath)' not found")
            throw ValidationError("Config file not found")
        }
        
        let content = try String(contentsOfFile: configPath)
        let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        print("Name | IP | Roles | Labels")
        print("-----|----|------|-------")
        for node in spec.nodes {
            let roles = node.roles.joined(separator: ",")
            let labels = node.labels?.map { "\($0.key)=\($0.value)" }.joined(separator: ",") ?? ""
            print("\(node.name) | \(node.ip) | \(roles) | \(labels)")
        }
    }
}

/// Add a new node to the cluster spec
struct NodeAddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new node to the cluster spec"
    )
    
    @Argument(help: "Node name (hostname)")
    var name: String?
    
    @Option(help: "Node IP address")
    var ip: String?
    
    @Option(help: "Comma-separated roles")
    var roles: String?
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    func run() throws {
        let configPath = config ?? "genestack-cluster.yaml"
        
        guard var spec = try? loadSpec(from: configPath) else {
            print("Error: Config file '\(configPath)' not found")
            throw ValidationError("Config file not found")
        }
        
        // Use provided args or prompt
        var nodeName = name
        var nodeIP = ip
        var nodeRoles = roles
        
        // Interactive mode only if --yes not set and args are missing
        if nodeName == nil {
            nodeName = prompt("Node name (hostname)", defaultValue: nil)
        }
        if nodeIP == nil {
            nodeIP = prompt("Node IP", defaultValue: nil)
        }
        if nodeRoles == nil {
            nodeRoles = prompt("Roles (comma-separated)", defaultValue: nil)
        }
        
        guard let finalName = nodeName else {
            print("Error: Node name is required")
            throw ValidationError("Missing node name")
        }
        guard let finalIP = nodeIP else {
            print("Error: Node IP is required")
            throw ValidationError("Missing IP")
        }
        guard let finalRoles = nodeRoles else {
            print("Error: Roles are required")
            throw ValidationError("Missing roles")
        }
        
        // Check for duplicate
        if spec.nodes.contains(where: { $0.name == finalName }) {
            print("Error: Node '\(finalName)' already exists")
            throw ValidationError("Node already exists")
        }
        
        let newNode = NodeSpec(
            name: finalName,
            ip: finalIP,
            roles: finalRoles.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            labels: nil,
            taints: nil,
            addresses: ["ansible_host": finalIP]
        )
        
        // Save with new node
        let newSpec = ClusterSpec(
            version: spec.version,
            metadata: spec.metadata,
            overrides: spec.overrides,
            kubernetes: spec.kubernetes,
            nodes: spec.nodes + [newNode],
            network: spec.network,
            storage: spec.storage,
            services: spec.services,
            environment: spec.environment
        )
        
        let yaml = try YAMLEncoder().encode(newSpec)
        try yaml.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
        
        print("Node '\(finalName)' added to '\(configPath)'")
    }
    
    private func prompt(_ message: String, defaultValue: String?) -> String? {
        let defaultValueStr = defaultValue ?? ""
        let promptText = "\(message) [\(defaultValueStr)]: "
        print(promptText, terminator: "")
        
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            return input
        }
        return defaultValue
    }
    
    private func loadSpec(from path: String) throws -> ClusterSpec {
        let content = try String(contentsOfFile: path)
        return try YAMLDecoder().decode(ClusterSpec.self, from: content)
    }
}

/// Remove a node from the cluster spec
struct NodeRemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a node from the cluster spec"
    )
    
    @Argument(help: "Node name")
    var name: String
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    func run() throws {
        let configPath = config ?? "genestack-cluster.yaml"
        
        guard FileManager.default.fileExists(atPath: configPath) else {
            print("Error: Config file '\(configPath)' not found")
            throw ValidationError("Config file not found")
        }
        
        let content = try String(contentsOfFile: configPath)
        let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        if let index = spec.nodes.firstIndex(where: { $0.name == name }) {
            var nodes = spec.nodes
            nodes.remove(at: index)
            
            let newSpec = ClusterSpec(
                version: spec.version,
                metadata: spec.metadata,
                overrides: spec.overrides,
                kubernetes: spec.kubernetes,
                nodes: nodes,
                network: spec.network,
                storage: spec.storage,
                services: spec.services,
                environment: spec.environment
            )
            
            let yaml = try YAMLEncoder().encode(newSpec)
            try yaml.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
            print("Node '\(name)' removed from '\(configPath)'")
        } else {
            print("Error: Node '\(name)' not found in spec")
            throw ValidationError("Node not found in spec")
        }
    }
}
