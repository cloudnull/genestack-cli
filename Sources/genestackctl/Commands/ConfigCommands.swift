//
// ConfigCommands.swift
// genestack-cli
//
// CLI commands for config management: validate, edit
//

import Foundation
import ArgumentParser
import Yams

/// Parent command for config management
struct ConfigCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage cluster configuration",
        subcommands: [ConfigValidateCommand.self, ConfigEditCommand.self]
    )
}

/// Validate the cluster spec
struct ConfigValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate the cluster spec"
    )
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    func run() throws {
        let configPath = config ?? "genestack-cluster.yaml"
        
        guard FileManager.default.fileExists(atPath: configPath) else {
            print("Error: Config file '\(configPath)' not found")
            throw ValidationError("Config file not found")
        }
        
        do {
            let content = try String(contentsOfFile: configPath)
            let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
            
            let validator = SpecValidator()
            let result = validator.validate(spec: spec)
            
            if result.isValid {
                print("✓ Cluster spec is valid")
                if !result.warnings.isEmpty {
                    print("Warnings:")
                    for warning in result.warnings {
                        print("  - \(warning)")
                    }
                }
            } else {
                print("✗ Cluster spec validation failed:")
                for error in result.errors {
                    print("  - \(error)")
                }
                for warning in result.warnings {
                    print("  - WARNING: \(warning)")
                }
                throw ExitCode.failure
            }
        } catch let decodingError as DecodingError {
            print("✗ Failed to parse cluster spec:")
            print("  \(decodingError)")
            throw ExitCode.failure
        }
    }
}

/// Edit the cluster spec in $EDITOR
struct ConfigEditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Open the cluster spec in $EDITOR"
    )
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    func run() throws {
        let configPath = config ?? "genestack-cluster.yaml"
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: configPath) {
            let spec = ClusterSpec(
                version: "1.0",
                metadata: MetadataSpec(clusterName: "", gatewayDomain: nil, acmeEmail: nil),
                overrides: nil,
                kubernetes: nil,
                nodes: [],
                network: nil,
                storage: nil,
                services: [],
                environment: nil
            )
            let yaml = try YAMLEncoder().encode(spec)
            try yaml.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
        }
        
        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: editor)
        process.arguments = [configPath]
        
        try process.run()
        process.waitUntilExit()
    }
}
