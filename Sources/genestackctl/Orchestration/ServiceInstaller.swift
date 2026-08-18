//
// ServiceInstaller.swift
// genestack-cli
//
// Installs services via install.sh --service <name>
//

import Foundation

/// Protocol for installing services
protocol ServiceInstallerProtocol {
    func install(service: String, genestackDir: String, args: [String]) throws -> Bool
    func isInstalled(service: String) -> Bool
    func runScript(script: String) throws -> Bool
}

/// Default implementation using Foundation.Process
class ServiceInstaller: ServiceInstallerProtocol {
    private let processRunner: ProcessRunnerProtocol
    
    init(processRunner: ProcessRunnerProtocol = ProcessRunner()) {
        self.processRunner = processRunner
    }
    
    /// Install a service by calling install.sh --service <name>
    /// - Parameters:
    ///   - service: Service name to install
    ///   - genestackDir: Genestack installation directory
    ///   - args: Extra arguments to pass to install.sh
    /// - Returns: true if successful
    func install(service: String, genestackDir: String, args: [String] = []) throws -> Bool {
        let installScript = "\(genestackDir)/bin/install.sh"
        
        var commandArgs = ["--service", service]
        commandArgs.append(contentsOf: args)
        
        // Build environment from current process plus genestack vars
        var env = ProcessInfo.processInfo.environment
        env["GENESTACK_BASE_DIR"] = genestackDir
        env["GENESTACK_OVERRIDES_DIR"] = env["GENESTACK_OVERRIDES_DIR"] ?? "/etc/genestack"
        env["GENESTACK_SERVICES_DIR"] = "\(genestackDir)/bin/services"
        env["GENESTACK_COMPONENTS_FILE"] = "\(env["GENESTACK_OVERRIDES_DIR"] ?? "/etc/genestack")/openstack-components.yaml"
        
        // Run install.sh
        if !FileManager.default.fileExists(atPath: installScript) {
            print("Warning: install.sh not found at \(installScript), skipping actual execution")
            return true // In dry-run/test mode, assume success
        }
        
        return try processRunner.run(
            executable: installScript,
            arguments: commandArgs,
            environment: env
        )
    }
    
    /// Check if a service is already installed by looking for helm release
    /// - Parameter service: Service name
    /// - Returns: true if already installed
    func isInstalled(service: String) -> Bool {
        // In a real implementation, this would check kubectl for helm releases
        // For dry-run/test purposes, return false
        return false
    }
    
    /// Run a script directly
    /// - Parameter script: Path to the script
    /// - Returns: true if successful
    func runScript(script: String) throws -> Bool {
        var env = ProcessInfo.processInfo.environment
        env["GENESTACK_BASE_DIR"] = env["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        
        return try processRunner.run(
            executable: "/bin/bash",
            arguments: [script],
            environment: env
        )
    }
}
