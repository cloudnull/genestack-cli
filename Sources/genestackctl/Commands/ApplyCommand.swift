//
// ApplyCommand.swift
// genestack-cli
//
// Execute installation pipeline from an existing cluster spec
//

import Foundation
import ArgumentParser
import Yams

/// Execute installation pipeline from existing cluster spec
struct ApplyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Execute installation pipeline from existing cluster spec"
    )
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    @Flag(help: "Skip confirmation prompts")
    var yes: Bool = false
    
    @Option(help: "Git repository URL for per-cluster helm/kustomize overrides")
    var overridesRepo: String?
    
    @Option(help: "Pipeline failure behavior: fail-fast, continue, or prompt (default)")
    var onFailure: String?
    
    @Option(help: "Override genestack installation directory")
    var genestackDir: String?
    
    @Flag(help: "Force re-install of already-provisioned services")
    var upgrade: Bool = false
    
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
        
        // Override overrides repo if specified on CLI
        var specToUse = spec
        if let overridesRepo = overridesRepo {
            specToUse = ClusterSpec(
                version: spec.version,
                metadata: spec.metadata,
                overrides: OverridesSpec(
                    repo: overridesRepo,
                    ref: spec.overrides?.ref ?? "main",
                    replaceBase: spec.overrides?.replaceBase ?? false
                ),
                kubernetes: spec.kubernetes,
                nodes: spec.nodes,
                network: spec.network,
                storage: spec.storage,
                services: spec.services,
                environment: spec.environment
            )
        }
        
        // Setup overrides
        let overridesManager = OverridesManager(genestackDir: genestackDir)
        let overridesDir: String
        do {
            overridesDir = try overridesManager.setupOverrides(spec: specToUse)
        } catch {
            print("Error setting up overrides: \(error.localizedDescription)")
            throw error
        }
        
        // Execute the installation pipeline
        print("Executing installation pipeline from spec: \(configPath)")
        let executor = PipelineExecutor(genestackDir: genestackDir)
        
        do {
            let result = try executor.execute(
                spec: specToUse,
                dryRun: false,
                upgrade: upgrade,
                onFailure: failureMode,
                overridesDir: overridesDir
            )
            
            if result.success {
                print("\n✓ Pipeline completed successfully!")
                print("Installed services: \(result.executedServices.joined(separator: ", "))")
            } else {
                print("\n✗ Pipeline completed with failures:")
                print("Failed services: \(result.failedServices.joined(separator: ", "))")
                throw ExitCode.failure
            }
        } catch {
            print("Error during pipeline execution: \(error.localizedDescription)")
            throw error
        }
    }
}
