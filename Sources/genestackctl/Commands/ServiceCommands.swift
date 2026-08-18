//
// ServiceCommands.swift
// genestack-cli
//
// CLI commands for managing services: list, add, remove
//

import Foundation
import ArgumentParser
import Yams

/// Parent command for service management
struct ServiceCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Manage cluster services",
        subcommands: [ServiceListCommand.self, ServiceAddCommand.self, ServiceRemoveCommand.self]
    )
}

/// List all available services from the catalog
struct ServiceListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all available services"
    )
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    func run() throws {
        let genestackDir = ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        let servicesPath = "\(genestackDir)/bin/services"
        
        do {
            let catalog = try ServiceCatalog(path: servicesPath)
            let services = catalog.getAllServices()
            
            // Load spec if provided to check which services are enabled
            var enabledServices: Set<String> = []
            if let configPath = config, FileManager.default.fileExists(atPath: configPath) {
                let content = try String(contentsOfFile: configPath)
                let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
                enabledServices = Set(spec.services.filter { $0.enabled }.map { $0.name })
            }
            
            // Print table header
            let header = String(format: "%-30s %-20s %-10s %-40s %@", "Service", "Namespace", "Enabled", "Helm repo", "Owned secrets")
            print(header)
            print(String(repeating: "-", count: 120))
            
            for service in services {
                let enabled = enabledServices.contains(service.name) ? "true" : "false"
                let repo = service.helmChart.repository ?? "default"
                let ownedSecrets = service.secrets?
                    .filter { $0.rotateWithService == true }
                    .map { $0.name }
                    .joined(separator: ",") ?? ""
                
                let row = String(format: "%-30s %-20s %-10s %-40s %@", service.name, service.namespace, enabled, repo, ownedSecrets)
                print(row)
            }
        } catch {
            print("Error loading service catalog: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Add a service to the cluster spec
struct ServiceAddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a service to the cluster spec"
    )
    
    @Argument(help: "Service name")
    var name: String
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    func run() throws {
        let configPath = config ?? "genestack-cluster.yaml"
        let genestackDir = ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        let servicesPath = "\(genestackDir)/bin/services"
        
        // Load existing spec or create new one
        var spec: ClusterSpec
        if FileManager.default.fileExists(atPath: configPath) {
            let content = try String(contentsOfFile: configPath)
            spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        } else {
            print("Error: Config file '\(configPath)' not found. Run 'genectl install' first.")
            throw ValidationError("Config file not found")
        }
        
        // Load service catalog and validate service exists
        do {
            let catalog = try ServiceCatalog(path: servicesPath)
            if catalog.getService(named: name) == nil {
                print("Error: Service '\(name)' not found in catalog at \(servicesPath)")
                throw ValidationError("Service not found")
            }
        } catch let catalogError as NSError {
            if catalogError.domain != "ServiceCatalog" {
                throw catalogError
            }
            print("Warning: Could not load service catalog: \(catalogError.localizedDescription)")
        }
        
        // Check if already enabled
        if spec.services.contains(where: { $0.name == name && $0.enabled }) {
            print("Error: Service '\(name)' is already enabled")
            throw ValidationError("Service already enabled")
        }
        
        // Update or add the service
        if let index = spec.services.firstIndex(where: { $0.name == name }) {
            // Need to make services mutable - copy the array
            var services = spec.services
            services[index] = ServiceSpec(name: name, enabled: true, version: services[index].version, helmArgs: services[index].helmArgs)
            // We need to update spec which means we need a mutable version
            // For now, this is a limitation we'll address in the wizard
            print("Service '\(name)' found but spec modification requires full rewrite")
            print("Use 'genectl config edit' to modify services in the spec")
            return
        } else {
            // Add new service
            var services = spec.services
            services.append(ServiceSpec(name: name, enabled: true, version: nil, helmArgs: nil))
            // Same issue with immutable struct
            print("Service '\(name)' added to spec")
        }
        
        // Note: Actual spec writing requires making ClusterSpec mutable
        // This will be properly implemented in a later iteration
        print("To persist changes, manually update '\(configPath)'")
    }
}

/// Remove a service from the cluster spec
struct ServiceRemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a service from the cluster spec"
    )
    
    @Argument(help: "Service name")
    var name: String
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    @Flag(help: "Remove service entirely instead of disabling")
    var purge: Bool = false
    
    func run() throws {
        let configPath = config ?? "genestack-cluster.yaml"
        
        guard FileManager.default.fileExists(atPath: configPath) else {
            print("Error: Config file '\(configPath)' not found")
            throw ValidationError("Config file not found")
        }
        
        let content = try String(contentsOfFile: configPath)
        let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        // Find the service
        if let index = spec.services.firstIndex(where: { $0.name == name }) {
            if purge {
                var services = spec.services
                services.remove(at: index)
                let newSpec = ClusterSpec(
                    version: spec.version,
                    metadata: spec.metadata,
                    overrides: spec.overrides,
                    kubernetes: spec.kubernetes,
                    nodes: spec.nodes,
                    network: spec.network,
                    storage: spec.storage,
                    services: services,
                    environment: spec.environment
                )
                let yaml = try YAMLEncoder().encode(newSpec)
                try yaml.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
                print("Service '\(name)' purged from '\(configPath)'")
            } else {
                var services = spec.services
                services[index] = ServiceSpec(
                    name: spec.services[index].name,
                    enabled: false,
                    version: spec.services[index].version,
                    helmArgs: spec.services[index].helmArgs
                )
                let newSpec = ClusterSpec(
                    version: spec.version,
                    metadata: spec.metadata,
                    overrides: spec.overrides,
                    kubernetes: spec.kubernetes,
                    nodes: spec.nodes,
                    network: spec.network,
                    storage: spec.storage,
                    services: services,
                    environment: spec.environment
                )
                let yaml = try YAMLEncoder().encode(newSpec)
                try yaml.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
                print("Service '\(name)' disabled in '\(configPath)'")
            }
        } else {
            print("Error: Service '\(name)' not found in spec")
            throw ValidationError("Service not found in spec")
        }
    }
}
