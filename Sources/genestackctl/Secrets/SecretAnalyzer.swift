//
// SecretAnalyzer.swift
// genestack-cli
//
// Discover secrets across services, analyze ownership, and plan rotation
//

import Foundation

/// Entry representing a secret's ownership details
struct SecretOwnershipEntry {
    let secretName: String
    let owner: String
    let namespace: String
    let keys: [String]
    let inK8s: Bool
    let helmFlags: [String]
    let path: String?
}

/// Analyzes secrets across the service catalog
class SecretAnalyzer {
    private let catalog: ServiceCatalog
    
    init(catalog: ServiceCatalog) {
        self.catalog = catalog
    }
    
    /// Analyze all secrets and their ownership
    /// - Returns: Map of secret ownership entries
    func analyzeOwnership() -> SecretOwnershipMap {
        var entries: [SecretOwnershipEntry] = []
        
        for service in catalog.getAllServices() {
            guard let secrets = service.secrets else { continue }
            
            for secret in secrets {
                if secret.rotateWithService == true {
                    entries.append(SecretOwnershipEntry(
                        secretName: secret.name,
                        owner: service.name,
                        namespace: service.namespace,
                        keys: secret.keys ?? [],
                        inK8s: false,
                        helmFlags: [],
                        path: secret.path
                    ))
                }
            }
        }
        
        return SecretOwnershipMap(secrets: entries)
    }
    
    /// Check if all required secrets for a service exist in k8s
    /// - Parameter service: Service name
    /// - Returns: true if all secrets exist, false if any missing
    func checkSecretsExist(for service: String) -> Bool {
        guard let serviceInfo = catalog.getService(named: service) else { return false }
        guard let secrets = serviceInfo.secrets else { return true }
        
        // In a real implementation, this would check k8s
        // For now, return false to indicate we can't verify
        return false
    }
    
    /// Plan the rotation of secrets for a service
    /// - Parameter service: Service whose secrets should be rotated
    /// - Returns: Rotation plan with owned secrets and impacted services
    func planRotation(for service: String) -> SecretRotationPlan {
        let ownedSecrets = catalog.getSecretsForRotation(service: service)
        
        // Find services that depend on this service
        let impactedServices: [String]
        if let serviceInfo = catalog.getService(named: service) {
            impactedServices = catalog.getServicesConsumingSecrets(from: service).map { $0.service }
        } else {
            impactedServices = []
        }
        
        return SecretRotationPlan(
            service: service,
            ownedSecrets: ownedSecrets,
            impactedServices: impactedServices
        )
    }
}
