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
                enabledServices = Set(spec.services?.filter { $0.enabled }.map { $0.name } ?? [])
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
        if spec.services?.contains(where: { $0.name == name && $0.enabled }) ?? false {
            print("Error: Service '\(name)' is already enabled")
            throw ValidationError("Service already enabled")
        }
        
        // Update or add the service
        if let services = spec.services, let index = services.firstIndex(where: { $0.name == name }) {
            let newServices = services.map { svc -> ServiceSpec in
                if svc.name == name {
                    return ServiceSpec(name: name, enabled: true, version: svc.version, helmArgs: svc.helmArgs)
                }
                return svc
            }
            
            let newSpec = ClusterSpec(
                version: spec.version,
                metadata: spec.metadata,
                overrides: spec.overrides,
                kubernetes: spec.kubernetes,
                nodes: spec.nodes ?? [],
                network: spec.network,
                storage: spec.storage,
                services: newServices,
                environment: spec.environment
            )
            
            let yaml = try YAMLEncoder().encode(newSpec)
            try yaml.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
            print("Service '\(name)' enabled in '\(configPath)'")
        } else if let services = spec.services {
            // Add new service
            let newServices = services + [ServiceSpec(name: name, enabled: true, version: nil, helmArgs: nil)]
            
            let newSpec = ClusterSpec(
                version: spec.version,
                metadata: spec.metadata,
                overrides: spec.overrides,
                kubernetes: spec.kubernetes,
                nodes: spec.nodes ?? [],
                network: spec.network,
                storage: spec.storage,
                services: newServices,
                environment: spec.environment
            )
            
            let yaml = try YAMLEncoder().encode(newSpec)
            try yaml.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
            print("Service '\(name)' added to '\(configPath)'")
        } else {
            // No services list at all - create one
            let newServices = [ServiceSpec(name: name, enabled: true, version: nil, helmArgs: nil)]
            
            let newSpec = ClusterSpec(
                version: spec.version,
                metadata: spec.metadata,
                overrides: spec.overrides,
                kubernetes: spec.kubernetes,
                nodes: spec.nodes ?? [],
                network: spec.network,
                storage: spec.storage,
                services: newServices,
                environment: spec.environment
            )
            
            let yaml = try YAMLEncoder().encode(newSpec)
            try yaml.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
            print("Service '\(name)' added to '\(configPath)'")
        }
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
        if let services = spec.services, let index = services.firstIndex(where: { $0.name == name }) {
            if purge {
                var newServices = services
                newServices.remove(at: index)
                let newSpec = ClusterSpec(
                    version: spec.version,
                    metadata: spec.metadata,
                    overrides: spec.overrides,
                    kubernetes: spec.kubernetes,
                    nodes: spec.nodes ?? [],
                    network: spec.network,
                    storage: spec.storage,
                    services: newServices,
                    environment: spec.environment
                )
                let yaml = try YAMLEncoder().encode(newSpec)
                try yaml.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
                print("Service '\(name)' purged from '\(configPath)'")
            } else {
                let newServices = services.map { svc -> ServiceSpec in
                    if svc.name == name {
                        return ServiceSpec(name: svc.name, enabled: false, version: svc.version, helmArgs: svc.helmArgs)
                    }
                    return svc
                }
                let newSpec = ClusterSpec(
                    version: spec.version,
                    metadata: spec.metadata,
                    overrides: spec.overrides,
                    kubernetes: spec.kubernetes,
                    nodes: spec.nodes ?? [],
                    network: spec.network,
                    storage: spec.storage,
                    services: newServices,
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
