//
// SecretOwnershipMap.swift
// genestack-cli
//
// Data structures for secret ownership tracking
//

import Foundation

/// Map of secret ownership entries
class SecretOwnershipMap {
    let secrets: [SecretOwnershipEntry]
    
    init(secrets: [SecretOwnershipEntry]) {
        self.secrets = secrets
    }
    
    /// Get all secrets owned by a specific service
    func getSecrets(for service: String) -> [SecretOwnershipEntry]? {
        let filtered = secrets.filter { $0.owner == service }
        return filtered.isEmpty ? nil : filtered
    }
    
    /// Get a specific secret by name
    func getSecret(named name: String) -> SecretOwnershipEntry? {
        return secrets.first { $0.secretName == name }
    }
    
    /// Get all secrets filtered by namespace
    func getSecrets(in namespace: String) -> [SecretOwnershipEntry] {
        return secrets.filter { $0.namespace == namespace }
    }
    
    /// Get all secrets formatted for display
    func getAllSecrets() -> [SecretOwnershipEntry] {
        return secrets
    }
}

/// Plan for rotating secrets for a service
struct SecretRotationPlan {
    let service: String
    let ownedSecrets: [SecretInfo]
    let impactedServices: [String]
    
    /// Get the ordered list of services for reinstallation after rotation
    /// Owner service comes first, then dependents in dependency order
    func getReinstallOrder(catalog: ServiceCatalog) -> [String] {
        var order: [String] = [service]
        
        // Add impacted services in dependency order
        for impactedService in impactedServices {
            if !order.contains(impactedService) {
                order.append(impactedService)
            }
        }
        
        return order
    }
}
