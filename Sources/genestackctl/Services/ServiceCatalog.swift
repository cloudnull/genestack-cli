//
// ServiceCatalog.swift
// genestack-cli
//
// Parses bin/services/*.yaml files to discover available services
// and their configuration (secrets, helm settings, dependencies).
//

import Foundation
import Yams

/// Loads and manages the service catalog from bin/services/ directory
class ServiceCatalog {
    private var services: [String: ServiceInfo] = [:]
    private let path: String
    
    /// Load all service definitions from the specified directory
    /// - Parameter path: Path to bin/services/ directory
    init(path: String) throws {
        self.path = path
        self.services = try ServiceCatalog.loadServices(from: path)
    }
    
    /// Parse all YAML files in the services directory
    /// - Parameter path: Path to the services directory
    /// - Returns: Dictionary of service name to ServiceInfo
    private static func loadServices(from path: String) throws -> [String: ServiceInfo] {
        var result: [String: ServiceInfo] = [:]
        
        guard let directoryEnumerator = FileManager.default.enumerator(atPath: path) else {
            throw NSError(domain: "ServiceCatalog", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot read service directory: \(path)"
            ])
        }
        
        let yamlFiles = directoryEnumerator.compactMap { $0 as? String }.filter { file in
            file.hasSuffix(".yaml") || file.hasSuffix(".yml")
        }
        
        for filename in yamlFiles {
            // Skip template and common files (as per spec)
            let basename = (filename as NSString).lastPathComponent
            if basename.contains("-template") ||
               basename.contains("-common") ||
               basename == "example-service.yaml" {
                continue
            }
            
            let fullPath = (path as NSString).appendingPathComponent(filename)
            
            do {
                let content = try String(contentsOfFile: fullPath, encoding: .utf8)
                let decoder = YAMLDecoder()
                let service = try decoder.decode(ServiceInfo.self, from: content)
                result[service.name] = service
            } catch {
                // Skip files that fail to parse
                print("Warning: Skipping invalid service file: \(filename) - \(error)")
                continue
            }
        }
        
        return result
    }
    
    /// Get a specific service by name
    /// - Parameter name: Service name
    /// - Returns: ServiceInfo if found, nil otherwise
    func getService(named name: String) -> ServiceInfo? {
        return services[name]
    }
    
    /// Get all services in the catalog (sorted by name)
    func getAllServices() -> [ServiceInfo] {
        return Array(services.values).sorted { $0.name < $1.name }
    }
    
    /// Get all service names
    func getAllServiceNames() -> [String] {
        return Array(services.keys).sorted()
    }
    
    /// Get secrets that rotate with a specific service
    /// - Parameter service: Service name
    /// - Returns: Array of SecretInfo that rotate with the service
    func getSecretsForRotation(service: String) -> [SecretInfo] {
        guard let svc = services[service] else { return [] }
        return svc.secrets?.filter { $0.rotateWithService == true } ?? []
    }
    
    /// Get services that depend on a given service (via secret references)
    /// - Parameter serviceName: The service that owns secrets others might reference
    /// - Returns: List of service names that depend on the given service
    func getDependentServices(of serviceName: String) -> [String] {
        var dependents: Set<String> = []
        
        for (name, service) in services {
            if let deps = service.dependencies {
                for dep in deps where dep.name == serviceName {
                    dependents.insert(name)
                }
            }
        }
        
        return Array(dependents)
    }
    
    /// Get services that consume secrets from a specific service
    /// - Parameter secretOwner: The service that owns the secrets
    /// - Returns: List of (serviceName, secretNames) tuples for services that consume secrets from secretOwner
    func getServicesConsumingSecrets(from secretOwner: String) -> [(service: String, secrets: [String])] {
        guard let ownerService = services[secretOwner] else { return [] }
        let ownedSecretNames = Set(ownerService.secrets?.map { $0.name } ?? [])
        
        var consumers: [(service: String, secrets: [String])] = []
        
        for (name, service) in services where name != secretOwner {
            // Check if this service's dependencies reference secrets from secretOwner
            if let deps = service.dependencies {
                for dep in deps where dep.name == secretOwner {
                    if let referencedSecrets = dep.secrets {
                        let filtered = referencedSecrets.filter { ownedSecretNames.contains($0) }
                        if !filtered.isEmpty {
                            consumers.append((service: name, secrets: filtered))
                        }
                    } else {
                        // Dependency without specified secrets means it uses all
                        consumers.append((service: name, secrets: Array(ownedSecretNames)))
                    }
                }
            }
        }
        
        return consumers
    }
}
