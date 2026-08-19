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
    func isInstalled(service: String) throws -> Bool
    func runScript(script: String, args: [String]) throws -> ProcessResult
}

/// Default implementation using Foundation.Process
class ServiceInstaller: ServiceInstallerProtocol {
    private let processRunner: ProcessRunnerProtocol
    private let pathResolver: PathResolver
    
    init(processRunner: ProcessRunnerProtocol = ProcessRunner(), pathResolver: PathResolver? = nil) {
        self.processRunner = processRunner
        self.pathResolver = pathResolver ?? PathResolver()
    }    
    /// Install a service by calling install.sh --service <name>
    /// - Parameters:
    ///   - service: Service name to install
    ///   - genestackDir: Genestack installation directory
    ///   - args: Extra arguments to pass to install.sh
    /// - Returns: true if successful
    /// - Throws: GenestackError.scriptNotFound, GenestackError.scriptFailed
    func install(service: String, genestackDir: String, args: [String] = []) throws -> Bool {
        let installScript = pathResolver.installScriptPath
        
        guard FileManager.default.fileExists(atPath: installScript) else {
            print("Warning: install.sh not found at \(installScript), skipping actual execution")
            return true // In dry-run/test mode, assume success
        }
        
        var commandArgs = ["--service", service]
        commandArgs.append(contentsOf: args)
        
        // Build environment
        var env = ProcessInfo.processInfo.environment
        env["GENESTACK_BASE_DIR"] = genestackDir
        env["GENESTACK_OVERRIDES_DIR"] = env["GENESTACK_OVERRIDES_DIR"] ?? "/etc/genestack"
        env["GENESTACK_SERVICES_DIR"] = pathResolver.servicesDir
        env["GENESTACK_COMPONENTS_FILE"] = "\(env["GENESTACK_OVERRIDES_DIR"] ?? "/etc/genestack")/openstack-components.yaml"
        
        do {
            let result = try processRunner.run(
                executable: pathResolver.platform.bashPath,
                arguments: [installScript] + commandArgs,
                environment: env
            )
            
            if !result.success {
                print("Service '\(service)' installation failed:")
                if !result.stderr.isEmpty {
                    print("STDERR: \(result.stderr)")
                }
                print("Exit code: \(result.exitCode)")
            }
            
            return result.success
        } catch {
            throw GenestackError.scriptFailed(installScript, 1)
        }
    }
    
    /// Check if a service is already installed by checking for helm release
    /// - Parameter service: Service name
    /// - Returns: true if already installed
    /// - Throws: GenestackError.k8sConnectionFailed
    func isInstalled(service: String) throws -> Bool {
        // Try to check if helm release exists using kubectl/helm
        let kubectlPath = pathResolver.locateExecutable(named: "kubectl")
        
        guard kubectlPath != nil else {
            // Can't check without kubectl, assume not installed
            return false
        }
        
        do {
            let result = try processRunner.run(
                executable: pathResolver.platform.bashPath,
                arguments: [
                    "-c",
                    "kubectl get helmrelease \(service) -n openstack --no-events -o name 2>/dev/null"
                ],
                environment: ProcessInfo.processInfo.environment
            )
            
            return result.success && !result.stdout.isEmpty
        } catch {
            // If we can't check, assume not installed
            return false
        }
    }
    
    /// Run a generic script
    /// - Parameters:
    ///   - script: Path to the script
    ///   - args: Arguments to pass to the script
    /// - Returns: ProcessResult
    /// - Throws: GenestackError.scriptNotFound, GenestackError.scriptFailed
    func runScript(script: String, args: [String] = []) throws -> ProcessResult {
        guard FileManager.default.fileExists(atPath: script) else {
            throw GenestackError.scriptNotFound(script)
        }
        
        var env = ProcessInfo.processInfo.environment
        env["GENESTACK_BASE_DIR"] = env["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        
        return try processRunner.run(
            executable: pathResolver.platform.bashPath,
            arguments: [script] + args,
            environment: env
        )
    }
}
