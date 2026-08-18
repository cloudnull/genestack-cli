//
// ServiceDependencyResolver.swift
// genestack-cli
//
// Resolves service dependency ordering based on secret cross-references
//

import Foundation

/// Error types for dependency resolution
enum DependencyResolutionError: Error, LocalizedError {
    case circularDependency([String])
    case unknownService(String)
    
    var errorDescription: String? {
        switch self {
        case .circularDependency(let cycle):
            return "Circular dependency detected: \(cycle.joined(separator: " -> "))"
        case .unknownService(let name):
            return "Unknown service referenced in dependencies: \(name)"
        }
    }
}

/// Resolves deployment order for services based on dependencies
class ServiceDependencyResolver {
    private let catalog: ServiceCatalog
    
    init(catalog: ServiceCatalog) {
        self.catalog = catalog
    }
    
    /// Resolve deployment order for a given set of services
    /// Uses topological sorting based on dependency relationships
    /// - Parameter serviceNames: Names of services to deploy
    /// - Returns: Ordered list of service names (dependencies first)
    /// - Throws: DependencyResolutionError if circular dependencies detected
    func resolveOrder(for serviceNames: [String]) throws -> [String] {
        var visited: Set<String> = []
        var inProgress: Set<String> = []
        var result: [String] = []
        var pathStack: [String] = []
        
        func dfs(name: String) throws {
            // Already fully processed
            if visited.contains(name) {
                return
            }
            
            // Cycle detection
            if inProgress.contains(name) {
                let cycle = extractCycle(from: pathStack, cyclePoint: name)
                throw DependencyResolutionError.circularDependency(cycle)
            }
            
            inProgress.insert(name)
            pathStack.append(name)
            
            // Process dependencies first
            if let service = catalog.getService(named: name),
               let dependencies = service.dependencies {
                for dep in dependencies {
                    // Only process dependencies that are in our target list
                    if serviceNames.contains(dep.name) {
                        try dfs(name: dep.name)
                    }
                }
            }
            
            inProgress.remove(name)
            visited.insert(name)
            result.append(name)
            
            // Remove from path stack when backtracking
            if let lastIdx = pathStack.lastIndex(of: name) {
                pathStack.removeSubrange(lastIdx...)
            }
        }
        
        // Process services in alphabetical order for determinism
        for name in serviceNames.sorted() {
            try dfs(name: name)
        }
        
        return result
    }
    
    /// Resolve deployment order including implicit dependencies
    /// - Parameter spec: Cluster spec with service configurations
    /// - Returns: Ordered list of service names
    /// - Throws: DependencyResolutionError
    func resolveOrder(from spec: ClusterSpec) throws -> [String] {
        let enabledServices = spec.services.filter { $0.enabled }.map { $0.name }
        return try resolveOrder(for: enabledServices)
    }
    
    /// Get all services that would be impacted by rotating secrets for a service
    /// - Parameter secretOwner: The service whose secrets are rotated
    /// - Returns: List of services in order, starting with the owner
    /// - Throws: DependencyResolutionError
    func getImpactedServices(for secretOwner: String) throws -> [String] {
        let allServices = catalog.getAllServiceNames()
        let allOrdered = try resolveOrder(for: allServices)
        
        // Find the index of the secret owner
        guard let ownerIndex = allOrdered.firstIndex(of: secretOwner) else {
            return [secretOwner] // If owner not found, just return it
        }
        
        // Return everything from the owner onwards
        return Array(allOrdered[ownerIndex...])
    }
    
    /// Get services that depend on a given service
    /// - Parameters:
    ///   - serviceName: The service to check dependencies of
    ///   - enabledOnly: If true, only consider enabled services
    /// - Returns: List of service names that depend on the given service
    func getDependents(of serviceName: String, enabledOnly: Bool = false) -> [String] {
        let targetServices = catalog.getAllServices()
        let allServices = enabledOnly ? targetServices.filter({ $0.enabled == true }) : targetServices
        
        var dependents: [String] = []
        
        for service in allServices where service.name != serviceName {
            if let deps = service.dependencies {
                for dep in deps where dep.name == serviceName {
                    dependents.append(service.name)
                    break
                }
            }
        }
        
        return dependents
    }
    
    /// Get the list of services that should be run in parallel
    /// - Parameter orderedServices: Services already in dependency order
    /// - Returns: Array of parallel groups (services within each group can run in parallel)
    func getParallelGroups(from orderedServices: [String]) -> [[String]] {
        var groups: [[String]] = []
        var processed: Set<String> = []
        
        var remaining = orderedServices
        
        while !remaining.isEmpty {
            var readyGroup: [String] = []
            
            for service in remaining {
                let serviceInfo = catalog.getService(named: service)
                let deps = serviceInfo?.dependencies ?? []
                
                // A service is ready if all its dependencies are processed
                let allDepsProcessed = deps.allSatisfy { dep in
                    !orderedServices.contains(dep.name) || processed.contains(dep.name)
                }
                
                if allDepsProcessed {
                    readyGroup.append(service)
                }
            }
            
            // If we can't make progress, add remaining to prevent infinite loop
            if readyGroup.isEmpty {
                readyGroup = remaining
            }
            
            groups.append(readyGroup)
            processed.formUnion(readyGroup)
            
            // Remove processed services from remaining
            remaining.removeAll { readyGroup.contains($0) }
        }
        
        return groups
    }
    
    private func extractCycle(from path: [String], cyclePoint: String) -> [String] {
        guard let startIndex = path.firstIndex(of: cyclePoint) else {
            return [cyclePoint]
        }
        return Array(path[startIndex...]) + [cyclePoint]
    }
}
