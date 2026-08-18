//
// InstallCommand.swift
// genestack-cli
//
// Full cluster installation wizard command
//

import Foundation
import ArgumentParser

/// Full cluster installation wizard
struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Full cluster installation wizard"
    )
    
    @Option(help: "Load existing cluster spec to pre-fill wizard answers")
    var config: String?
    
    @Flag(help: "Skip confirmation prompts; use defaults for unanswered questions")
    var yes: Bool = false
    
    @Flag(help: "Generate cluster spec only; do not execute installer")
    var skipInstall: Bool = false
    
    @Option(help: "Override default output path")
    var output: String?
    
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
            print("Error: Invalid --on-failure mode '\(onFailure ?? "")'. Must be: fail-fast, continue, or prompt")
            throw ValidationError("Invalid failure mode")
        }
        
        // Run the interactive wizard
        let wizard = Wizard(config: config)
        var spec = try wizard.run(assumeDefaults: yes)
        
        // Override spec from CLI flags if provided
        if let overridesRepo = overridesRepo {
            spec = ClusterSpec(
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
        
        // Validate the spec
        let validator = SpecValidator()
        let validationResult = validator.validate(spec: spec)
        
        if !validationResult.isValid {
            print("Error: Generated spec failed validation:")
            for error in validationResult.errors {
                print("  - \(error)")
            }
            throw ValidationError("Spec validation failed")
        }
        
        // Write the spec
        let outputPath = output ?? "genestack-cluster.yaml"
        try spec.save(to: outputPath)
        print("\nCluster spec written to: \(outputPath)")
        
        // Print validation warnings
        if !validationResult.warnings.isEmpty {
            print("\nWarnings:")
            for warning in validationResult.warnings {
                print("  - \(warning)")
            }
        }
        
        // Execute installation pipeline unless skipped
        if skipInstall {
            print("\n--skip-install specified: Skipping installation pipeline")
            return
        }
        
        // Setup overrides if specified
        let overridesManager = OverridesManager(genestackDir: genestackDir)
        let overridesDir: String
        do {
            overridesDir = try overridesManager.setupOverrides(spec: spec)
        } catch {
            print("Error setting up overrides: \(error.localizedDescription)")
            throw error
        }
        
        // Execute the installation pipeline
        print("\nStarting installation pipeline...")
        let executor = PipelineExecutor(genestackDir: genestackDir)
        
        do {
            let result = try executor.execute(
                spec: spec,
                dryRun: false,
                upgrade: upgrade,
                onFailure: failureMode,
                overridesDir: overridesDir
            )
            
            if result.success {
                print("\n✓ Installation completed successfully!")
                print("Installed services: \(result.executedServices.joined(separator: ", "))")
            } else {
                print("\n✗ Installation completed with failures:")
                print("Failed services: \(result.failedServices.joined(separator: ", "))")
                throw ExitCode.failure
            }
        } catch {
            print("Error during installation: \(error.localizedDescription)")
            throw error
        }
    }
}
