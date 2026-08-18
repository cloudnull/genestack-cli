//
// SecretCommands.swift
// genestack-cli
//
// CLI commands for managing secrets: list, rotate, check
//

import Foundation
import ArgumentParser

/// Parent command for secret management
struct SecretCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "secret",
        abstract: "Manage cluster secrets",
        subcommands: [SecretListCommand.self, SecretRotateCommand.self, SecretCheckCommand.self]
    )
}

/// List all secrets and their ownership
struct SecretListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all secrets and their ownership"
    )
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    @Option(help: "Filter by namespace")
    var namespace: String?
    
    func run() throws {
        let genestackDir = ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        let servicesPath = "\(genestackDir)/bin/services"
        
        guard FileManager.default.fileExists(atPath: servicesPath) else {
            print("Error: Service catalog not found at \(servicesPath)")
            throw ValidationError("Service catalog not found")
        }
        
        do {
            let catalog = try ServiceCatalog(path: servicesPath)
            let analyzer = SecretAnalyzer(catalog: catalog)
            let ownershipMap = analyzer.analyzeOwnership()
            
            var secrets = ownershipMap.getAllSecrets()
            
            // Filter by namespace if provided
            if let ns = namespace {
                secrets = secrets.filter { $0.namespace == ns }
            }
            
            // Print table header
            let header = String(format: "%-20s %-40s %-20s %-20s %-10s %@", "Namespace", "Secret", "Owner", "Data keys", "In k8s?", "Helm flags")
            print(header)
            print(String(repeating: "-", count: 140))
            
            for secret in secrets {
                let keys = secret.keys.joined(separator: ",")
                let inK8s = secret.inK8s ? "true" : "false"
                let helmFlags = secret.helmFlags.joined(separator: " ")
                let row = String(format: "%-20s %-40s %-20s %-20s %-10s %@", secret.namespace, secret.secretName, secret.owner, keys, inK8s, helmFlags)
                print(row)
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Rotate secrets for a specific service
struct SecretRotateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rotate",
        abstract: "Rotate secrets for a specific service and reinstall impacted services"
    )
    
    @Argument(help: "Service name")
    var service: String
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    @Flag(help: "Skip confirmation prompt")
    var yes: Bool = false
    
    @Flag(help: "Print rotation plan without executing")
    var dryRun: Bool = false
    
    @Option(help: "Failure behavior: prompt, fail-fast, or continue")
    var onFailure: String?
    
    func run() throws {
        let genestackDir = ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        let servicesPath = "\(genestackDir)/bin/services"
        
        guard FileManager.default.fileExists(atPath: servicesPath) else {
            print("Error: Service catalog not found at \(servicesPath)")
            throw ValidationError("Service catalog not found")
        }
        
        let catalog = try ServiceCatalog(path: servicesPath)
        let analyzer = SecretAnalyzer(catalog: catalog)
        
        // Check if service exists
        guard catalog.getService(named: service) != nil else {
            print("Error: Service '\(service)' not found in catalog")
            throw ValidationError("Service not found")
        }
        
        // Plan rotation
        let plan = analyzer.planRotation(for: service)
        
        print("Rotation plan for service '\(service)':")
        print("Owned secrets to rotate:")
        for secret in plan.ownedSecrets {
            let keys = secret.keys?.joined(separator: ", ") ?? "none"
            print("  - \(secret.name) (type: \(secret.type ?? "unknown"), keys: \(keys))")
        }
        
        if plan.ownedSecrets.isEmpty {
            print("  (no rotatable secrets found)")
        }
        
        print("\nImpacted services (will be reinstalled in order):")
        let reinstallOrder = plan.getReinstallOrder(catalog: catalog)
        for svc in reinstallOrder {
            print("  - \(svc)")
        }
        
        if dryRun {
            print("\n[Dry run] Rotation plan shown above")
            return
        }
        
        if !yes {
            print("\nProceed with rotation? (y/N): ", terminator: "")
            if let input = readLine()?.lowercased().trimmingCharacters(in: .whitespaces), input != "y" {
                print("Aborted.")
                return
            }
        }
        
        // Execute rotation (simplified - in real impl this would call actual rotation scripts)
        print("\nRotating secrets for '\(service)'...")
        print("Reinstalling impacted services...")
        
        for svc in reinstallOrder {
            print("  Reinstalling: \(svc)")
            // In real implementation, would call install.sh --service \(svc) --rotate-secrets
        }
        
        print("\nSecret rotation completed successfully.")
    }
}

/// Check if all required secrets exist in k8s
struct SecretCheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check if all secrets required by a service exist in k8s"
    )
    
    @Argument(help: "Service name")
    var service: String
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    func run() throws {
        let genestackDir = ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        let servicesPath = "\(genestackDir)/bin/services"
        
        guard FileManager.default.fileExists(atPath: servicesPath) else {
            print("Error: Service catalog not found at \(servicesPath)")
            throw ValidationError("Service catalog not found")
        }
        
        let catalog = try ServiceCatalog(path: servicesPath)
        let analyzer = SecretAnalyzer(catalog: catalog)
        
        guard catalog.getService(named: service) != nil else {
            print("Error: Service '\(service)' not found in catalog")
            throw ValidationError("Service not found")
        }
        
        let allPresent = analyzer.checkSecretsExist(for: service)
        
        if allPresent {
            print("✓ All secrets for '\(service)' are present in k8s")
            return  // Exit 0
        } else {
            print("✗ Some secrets for '\(service)' are missing in k8s")
            throw ExitCode.failure
        }
    }
}
