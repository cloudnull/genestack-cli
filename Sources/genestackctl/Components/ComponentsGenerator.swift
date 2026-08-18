//
// ComponentsGenerator.swift
// genestack-cli
//
// Generates openstack-components.yaml from the cluster spec
//

import Foundation

/// Generates openstack-components.yaml from the cluster spec's services list
class ComponentsGenerator {
    
    /// Generate openstack-components.yaml content from cluster spec
    /// - Parameter spec: Cluster specification
    /// - Returns: YAML string representing the components file
    func generate(spec: ClusterSpec) throws -> String {
        var yamlLines: [String] = []
        yamlLines.append("components:")
        
        // Sort services by name for deterministic output
        let sortedServices = spec.services.sorted { $0.name < $1.name }
        
        for service in sortedServices {
            let enabledStr = service.enabled ? "true" : "false"
            yamlLines.append("  \(service.name): \(enabledStr)")
        }
        
        return yamlLines.joined(separator: "\n")
    }
    
    /// Generate components from a service catalog and cluster spec
    /// This ensures all known services are listed, not just those in the spec
    /// - Parameters:
    ///   - spec: Cluster specification
    ///   - catalog: Loaded service catalog
    /// - Returns: YAML string of the components
    func generateFromCatalog(spec: ClusterSpec, catalog: ServiceCatalog) throws -> String {
        var yamlLines: [String] = []
        yamlLines.append("components:")
        
        // Get all services from catalog to ensure all 50+ are listed
        let allServices = catalog.getAllServices()
        
        // Create a lookup of enabled services from spec
        let enabledServices = Set(spec.services.filter { $0.enabled }.map { $0.name })
        
        for service in allServices.sorted(by: { $0.name < $1.name }) {
            let enabled = enabledServices.contains(service.name)
            let enabledStr = enabled ? "true" : "false"
            yamlLines.append("  \(service.name): \(enabledStr)")
        }
        
        return yamlLines.joined(separator: "\n")
    }
}
