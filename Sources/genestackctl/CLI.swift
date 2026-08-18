//
// CLI.swift
// genestack-cli
//
// Main CLI entry point with command registration
//

import Foundation
import ArgumentParser

@main
struct GenestackCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "genectl",
        abstract: "Genestack Cluster Installation CLI",
        version: "1.0.0",
        subcommands: [
            InstallCommand.self,
            ApplyCommand.self,
            ServiceCommands.self,
            NodeCommands.self,
            SecretCommands.self,
            ConfigCommands.self
        ]
    )
}
