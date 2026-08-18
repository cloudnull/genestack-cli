import Foundation
import ArgumentParser

@main
struct GenestackCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "genectl",
        abstract: "Genestack Cluster Installation CLI",
        version: "1.0.0"
    )
}
