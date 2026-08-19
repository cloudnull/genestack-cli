//
// UpgradeCommand.swift
// genestack-cli
//
// Handles cluster upgrades with proper ordering and safety checks
//

import Foundation
import ArgumentParser
import Yams

/// Upgrade Genestack cluster components
struct UpgradeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upgrade",
        abstract: "Upgrade cluster components safely"
    )
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    @Option(help: "Specific service to upgrade (if omitted, upgrades all enabled services)")
    var service: String?
    
    @Flag(help: "Perform a dry run without making changes")
    var dryRun: Bool = false
    
    @Flag(help: "Skip confirmation prompts")
    var yes: Bool = false
    
    @Option(help: "Failure behavior: fail-fast, continue, or prompt (default)")
    var onFailure: String?
    
    @Option(help: "Override genestack installation directory")
    var genestackDir: String?
    
    func run() throws {
        // Validate onFailure parameter
        let failureMode: FailureMode
        switch onFailure ?? "prompt" {
        case "fail-fast":
            failureMode = .failFast
        case "continue":
            failureMode = .continueOnFailure
        case "prompt":
            failureMode = .prompt
        default:
            print("Error: Invalid --on-failure mode. Must be: fail-fast, continue, or prompt")
            throw ValidationError("Invalid failure mode")
        }
        
        // Load the spec
        let configPath = config ?? "genestack-cluster.yaml"
        guard FileManager.default.fileExists(atPath: configPath) else {
            print("Error: Config file '\(configPath)' not found")
            throw ValidationError("Config file not found")
        }
        
        let content = try String(contentsOfFile: configPath)
        let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
        
        let pathResolver = PathResolver(genestackDir: genestackDir)
        let servicesPath = pathResolver.resolvePath(for: "bin/services")
        
        print("=== Genestack Cluster Upgrade ===")
        print("Cluster: \(spec.metadata.clusterName)")
        print("Target: \(service ?? "all services")")
        print("Mode: \(dryRun ? "dry-run" : "execute")\n")
        
        if !yes && !dryRun {
            print("This will upgrade cluster components. Continue? (y/N): ", terminator: "")
            let response = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) ?? "n"
            if response != "y" {
                print("Upgrade cancelled.")
                return
            }
        }
        
        // Load service catalog
        guard let catalog = try? ServiceCatalog(path: servicesPath) else {
            print("Error: Cannot load service catalog from \(servicesPath)")
            throw ValidationError("Service catalog not found")
        }
        
        // Determine which services to upgrade
        let servicesToUpgrade: [String]
        if let service = self.service {
            // Validate service exists
            guard catalog.getService(named: service) != nil else {
                print("Error: Service '\(service)' not found in catalog")
                throw ValidationError("Service not found")
            }
            servicesToUpgrade = [service]
        } else {
            servicesToUpgrade = spec.services?.filter { $0.enabled }.map { $0.name } ?? []
        }
        
        if servicesToUpgrade.isEmpty {
            print("No services to upgrade.")
            return
        }
        
        print("Services to upgrade:")
        for svc in servicesToUpgrade.sorted() {
            print("  - \(svc)")
        }
        print("")
        
        // Resolve dependency order
        let resolver = ServiceDependencyResolver(catalog: catalog)
        let orderedServices: [String]
        do {
            orderedServices = try resolver.resolveOrder(for: servicesToUpgrade)
        } catch {
            throw GenestackError.dependencyResolutionFailed(error.localizedDescription)
        }
        
        print("Upgrade order:")
        for (index, svc) in orderedServices.enumerated() {
            print("  \(index + 1). \(svc)")
        }
        print("")
        
        if dryRun {
            print("Dry run completed. No changes were made.")
            return
        }
        
        // Execute upgrade
        let executor = PipelineExecutor(genestackDir: genestackDir, catalog: catalog)
        let result = try executor.execute(
            spec: spec,
            dryRun: false,
            upgrade: true,
            onFailure: failureMode
        )
        
        if result.success {
            print("\n✅ Upgrade completed successfully!")
            print("Upgraded services: \(result.executedServices.joined(separator: ", "))")
        } else {
            print("\n❌ Upgrade completed with failures:")
            print("Failed services: \(result.failedServices.joined(separator: ", "))")
            throw ExitCode.failure
        }
    }
}
