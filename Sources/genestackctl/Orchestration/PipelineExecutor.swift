//
// PipelineExecutor.swift
// genestack-cli
//
// Executes the installation pipeline for the cluster
//

import Foundation
import Yams

/// How pipeline errors should be handled
enum FailureMode {
    case failFast
    case continueOnFailure
    case prompt
}

/// Result of a pipeline execution
struct ExecutionResult {
    let success: Bool
    let executedServices: [String]
    let failedServices: [String]
    let output: String
}

/// Executes the installation pipeline for a cluster
class PipelineExecutor {
    private let genestackDir: String
    private let serviceInstaller: ServiceInstallerProtocol
    private let catalog: ServiceCatalog?
    
    /// Infrastructure services that must be installed in order before OpenStack services
    private static let infrastructureSteps: [String] = [
        "kube-ovn",
        "longhorn", 
        "kube-prometheus-stack",
        "cert-manager",
        "metallb",
        "envoy-gateway",
        "mariadb-operator",
        "memcached",
        "libvirt",
        "redis-operator",
        "redis-replication",
        "redis-sentinel"
    ]
    
    init(
        genestackDir: String?,
        installer: ServiceInstallerProtocol? = nil,
        catalog: ServiceCatalog? = nil
    ) {
        self.genestackDir = genestackDir ?? ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        self.serviceInstaller = installer ?? ServiceInstaller()
        self.catalog = catalog
    }
    
    /// Execute the full installation pipeline
    /// - Parameters:
    ///   - spec: Cluster specification
    ///   - dryRun: If true, print actions without executing
    ///   - upgrade: If true, force reinstall of already-provisioned services
    ///   - onFailure: How to handle failures
    ///   - overridesDir: Directory containing overrides
    /// - Returns: ExecutionResult with status
    /// - Throws: GenestackError on critical failures
    func execute(
        spec: ClusterSpec,
        dryRun: Bool = false,
        upgrade: Bool = false,
        onFailure: FailureMode = .prompt,
        overridesDir: String = "/etc/genestack"
    ) throws -> ExecutionResult {
        var executedServices: [String] = []
        var failedServices: [String] = []
        var output: String = ""
        


        
        // Step 1: Generate ansible inventory
        output += "Step 1: Generating Ansible inventory...\n"
        let inventoryGen = InventoryGenerator()
        let inventory = try inventoryGen.generate(spec: spec)
        
        if !dryRun {
            let inventoryPath = "\(overridesDir)/inventory/inventory.yaml"
            try ensureDirectoryExists(for: inventoryPath)
            try inventory.write(toFile: inventoryPath, atomically: true, encoding: .utf8)
            output += "Generated Ansible inventory at: \(inventoryPath)\n"
    
        } else {
            output += "[Dry run] Would generate Ansible inventory\n"
        }
        
        // Step 2: Generate openstack-components.yaml
        output += "Step 2: Generating openstack-components.yaml...\n"
        let componentsGen = ComponentsGenerator()
        let components: String
        let effectiveCatalog: ServiceCatalog?
        
        if let catalog = self.catalog {
            effectiveCatalog = catalog
        } else {
            effectiveCatalog = try? ServiceCatalog(path: "\(genestackDir)/bin/services")
        }
        
        if let catalog = effectiveCatalog {
            components = try componentsGen.generateFromCatalog(spec: spec, catalog: catalog)
        } else {
            components = try componentsGen.generate(spec: spec)
        }
        
        if !dryRun {
            let componentsPath = "\(overridesDir)/openstack-components.yaml"
            try ensureDirectoryExists(for: componentsPath)
            try components.write(toFile: componentsPath, atomically: true, encoding: .utf8)
            output += "Generated openstack-components.yaml at: \(componentsPath)\n"
    
        } else {
            output += "[Dry run] Would generate openstack-components.yaml\n"
        }
        
        // Step 3: Run bootstrap.sh (idempotent)
        if !dryRun {
            output += "Step 3: Running bootstrap.sh...\n"
    
            do {
                let result = try serviceInstaller.runScript(script: "\(genestackDir)/bin/bootstrap.sh", args: [])
                if !result.success {
                    throw GenestackError.scriptFailed("bootstrap.sh", result.exitCode)
                }
                output += "bootstrap.sh completed successfully\n"
        
            } catch let error as GenestackError {
                throw error
            } catch {
                throw GenestackError.scriptFailed("bootstrap.sh", -1)
            }
        } else {
            output += "[Dry run] Would run bootstrap.sh\n"
        }
        
        // Step 4: Execute infrastructure services
        output += "Step 4: Setting up infrastructure services...\n"

        
        for step in Self.infrastructureSteps {
            if dryRun {
                output += "[Dry run] Would install: \(step)\n"
                continue
            }
            
            let shouldInstall: Bool
            if upgrade {
                shouldInstall = true
            } else {
                do {
                    shouldInstall = !(try serviceInstaller.isInstalled(service: step))
                } catch {
                    shouldInstall = true // If we can't check, try to install
                }
            }
            
            if shouldInstall {
        
                do {
                    let success = try serviceInstaller.install(service: step, genestackDir: genestackDir, args: [])
                    if success {
                        executedServices.append(step)
                
                    } else {
                        throw GenestackError.scriptFailed("install.sh", 1)
                    }
                } catch {
                    failedServices.append(step)
            
                    if !FailureHandler.handle(service: step, error: error, mode: onFailure) {
                        break
                    }
                }
            }
        }
        
        // Step 5: Resolve service order and execute OpenStack services
        if let catalog = effectiveCatalog {
            output += "Step 5: Installing OpenStack services in dependency order...\n"
    
            
            let resolver = ServiceDependencyResolver(catalog: catalog)
            let enabledServices = spec.services?.filter { $0.enabled }.map { $0.name } ?? []
            var orderedServices: [String]
            
            do {
                orderedServices = try resolver.resolveOrder(for: enabledServices)
            } catch {
                throw GenestackError.dependencyResolutionFailed(error.localizedDescription)
            }
            
            let nonKeystoneServices = orderedServices.filter { $0 != "keystone" }
            
            // Handle keystone first
            if let keystoneIndex = orderedServices.firstIndex(of: "keystone") {
                let keystoneService = orderedServices.remove(at: keystoneIndex)
                output += "Installing keystone (dependency for all OpenStack services)...\n"
                try installService(
                    service: keystoneService,
                    upgrade: upgrade,
                    dryRun: dryRun,
                    onFailure: onFailure,
                    executed: &executedServices,
                    failed: &failedServices,
                    output: &output
                )
            }
            
            // Install services in dependency order (can be parallelized later)
            for service in nonKeystoneServices {
                output += "Installing: \(service)...\n"
                try installService(
                    service: service,
                    upgrade: upgrade,
                    dryRun: dryRun,
                    onFailure: onFailure,
                    executed: &executedServices,
                    failed: &failedServices,
                    output: &output
                )
            }
            
            // Generate OpenStack RC file for user
            if !dryRun && !executedServices.isEmpty {
                output += "\nInstallation complete. Generating OpenStack RC file...\n"
                output += "Run 'openstack rc' to generate your OpenStack RC file.\n"
            }
        }
        
        let success = failedServices.isEmpty

        
        return ExecutionResult(
            success: success,
            executedServices: executedServices,
            failedServices: failedServices,
            output: output
        )
    }
    
    private func installService(
        service: String,
        upgrade: Bool,
        dryRun: Bool,
        onFailure: FailureMode,
        executed: inout [String],
        failed: inout [String],
        output: inout String
    ) throws {
        let shouldInstall: Bool
        if dryRun {
            output += "[Dry run] Would install service: \(service)\n"
            executed.append(service)
            return
        }
        
        if upgrade {
            shouldInstall = true
        } else {
            do {
                shouldInstall = !(try serviceInstaller.isInstalled(service: service))
            } catch {
                shouldInstall = true
            }
        }
        
        if shouldInstall {
            do {
                let success = try serviceInstaller.install(service: service, genestackDir: genestackDir, args: [])
                if success {
                    executed.append(service)
                } else {
                    failed.append(service)
                    if !FailureHandler.handle(service: service, error: GenestackError.scriptFailed("install.sh", 1), mode: onFailure) {
                        // Stop execution
                    }
                }
            } catch {
                failed.append(service)
                if !FailureHandler.handle(service: service, error: error, mode: onFailure) {
                    // Stop execution
                }
            }
        }
    }
    
    private func ensureDirectoryExists(for filePath: String) throws {
        let directory = (filePath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: directory) {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
    }
}
