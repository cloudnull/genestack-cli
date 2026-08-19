//
// StatusCommand.swift
// genestack-cli
//
// Checks cluster health and deployment status
//

import Foundation
import ArgumentParser
import Yams

/// Check cluster deployment and health status
struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check cluster deployment and health status"
    )
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    @Option(help: "Genestack installation directory")
    var genestackDir: String?
    
    @Flag(help: "Show detailed status including individual services")
    var verbose: Bool = false
    
    func run() throws {
        let pathResolver = PathResolver(genestackDir: genestackDir)
        let servicesPath = pathResolver.servicesDir
        
        print("=== Genestack Cluster Status ===\n")
        
        // Check 1: Genestack installation
        if FileManager.default.fileExists(atPath: pathResolver.path) {
            print("✅ Genestack installation found at: \(pathResolver.path)")
        } else {
            print("❌ Genestack installation not found at: \(pathResolver.path)")
            print("   Install Genestack or set GENESTACK_BASE_DIR environment variable")
        }
        
        // Check 2: Service catalog
        if FileManager.default.fileExists(atPath: servicesPath) {
            do {
                let catalog = try ServiceCatalog(path: servicesPath)
                let services = catalog.getAllServices()
                print("✅ Service catalog loaded: \(services.count) services")
                
                if verbose {
                    print("\nServices:")
                    for service in services {
                        let secrets = service.secrets?.count ?? 0
                        let deps = service.dependencies?.count ?? 0
                        print("  - \(service.name) (namespace: \(service.namespace), secrets: \(secrets), deps: \(deps))")
                    }
                }
            } catch {
                print("⚠️  Service catalog error: \(error.localizedDescription)")
            }
        } else {
            print("⚠️  Service catalog not found at: \(servicesPath)")
        }
        
        // Check 3: Cluster spec
        let configPath = config ?? "genestack-cluster.yaml"
        if FileManager.default.fileExists(atPath: configPath) {
            do {
                let content = try String(contentsOfFile: configPath)
                let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
                
                print("✅ Cluster spec found: \(configPath)")
                print("   Cluster name: \(spec.metadata.clusterName)")
                if let gateway = spec.metadata.gatewayDomain {
                    print("   Gateway domain: \(gateway)")
                }
                
                let enabledServices = spec.services?.filter { $0.enabled }.count ?? 0
                let totalServices = spec.services?.count ?? 0
                print("   Services: \(enabledServices)/\(totalServices) enabled")
                
                if let nodes = spec.nodes {
                    print("   Nodes: \(nodes.count)")
                    if verbose {
                        for node in nodes {
                            let roles = node.roles.joined(separator: ", ")
                            print("     - \(node.name) (\u{200B}\(node.ip)): \(roles)")
                        }
                    }
                }
                
                // Check for validation issues
                let validator = SpecValidator()
                let result = validator.validate(spec: spec)
                if !result.isValid {
                    print("\n❌ Spec validation errors:")
                    for error in result.errors {
                        print("   - \(error)")
                    }
                }
                if !result.warnings.isEmpty {
                    print("\n⚠️  Spec validation warnings:")
                    for warning in result.warnings {
                        print("   - \(warning)")
                    }
                }
                
            } catch {
                print("❌ Error parsing cluster spec: \(error.localizedDescription)")
            }
        } else {
            print("⚠️  Cluster spec not found: \(configPath)")
        }
        
        // Check 4: Overrides directory
        let overridesDir = ProcessInfo.processInfo.environment["GENESTACK_OVERRIDES_DIR"] ?? "/etc/genestack"
        if FileManager.default.fileExists(atPath: overridesDir) {
            print("\n✅ Overrides directory exists: \(overridesDir)")
            
            // Check for generated files
            let inventoryPath = "\(overridesDir)/inventory/inventory.yaml"
            let componentsPath = "\(overridesDir)/openstack-components.yaml"
            
            if FileManager.default.fileExists(atPath: inventoryPath) {
                print("  - Ansible inventory: \(inventoryPath)")
            }
            
            if FileManager.default.fileExists(atPath: componentsPath) {
                print("  - OpenStack components: \(componentsPath)")
            }
        }
        
        // Check 5: Installed services (requires kubectl)
        if let kubectlPath = pathResolver.locateExecutable(named: "kubectl") {
            print("\nChecking installed services via kubectl...")
            
            let processRunner = ProcessRunner()
            var env = ProcessInfo.processInfo.environment
            env["GENESTACK_BASE_DIR"] = pathResolver.path
            env["GENESTACK_OVERRIDES_DIR"] = env["GENESTACK_OVERRIDES_DIR"] ?? "/etc/genestack"
            env["GENESTACK_SERVICES_DIR"] = pathResolver.servicesDir
            env["GENESTACK_COMPONENTS_FILE"] = "\(env["GENESTACK_OVERRIDES_DIR"] ?? "/etc/genestack")/openstack-components.yaml"
            
            do {
                // Check OpenStack services
                let openstackServices = ["keystone", "glance", "nova", "neutron", "cinder", "horizon", "placement"]
                var readyServices: [String] = []
                var notReadyServices: [String] = []
                
                for service in openstackServices {
                    do {
                        let result = try processRunner.run(
                            executable: pathResolver.platform.bashPath,
                            arguments: [
                                "-c",
                                "kubectl get deployment \(service)-api -n openstack --no-events -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo \"0\""
                            ],
                            environment: env
                        )
                        
                        if let readyReplicas = Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)),
                           readyReplicas > 0 {
                            readyServices.append(service)
                        } else {
                            notReadyServices.append(service)
                        }
                    } catch {
                        notReadyServices.append(service)
                    }
                }
                
                if readyServices.count > 0 {
                    print("✅ Ready services: \(readyServices.joined(separator: ", "))")
                }
                
                if notReadyServices.count > 0 {
                    if verbose {
                        print("⚠️  Not ready services: \(notReadyServices.joined(separator: ", "))")
                    }
                }
                
                // Show total count
                let total = readyServices.count + notReadyServices.count
                print("Total: \(readyServices.count)/\(total) services ready")
                
            } catch {
                print("⚠️  Error checking Kubernetes: \(error.localizedDescription)")
            }
        } else {
            print("\n⚠️  kubectl not found - cannot check live cluster status")
            print("   Set GENESTACK_BASE_DIR or install kubectl to enable status checks")
        }
        
        print("\n=== Status Check Complete ===")
    }
}
