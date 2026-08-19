//
// SpecValidator.swift
// genestack-cli
//
// Validates ClusterSpec for internal consistency and required fields
//

import Foundation

/// Represents the result of a spec validation
struct ValidationResult: Equatable {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
}

/// Validates cluster specifications for correctness
class SpecValidator {
    
    /// Validate a ClusterSpec for structural correctness
    /// - Parameter spec: The cluster specification to validate
    /// - Returns: ValidationResult indicating success or listing errors
    func validate(spec: ClusterSpec) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Validate version
        if spec.version != "1.0" {
            errors.append("Unsupported spec version: \(spec.version). Only \"1.0\" is supported.")
        }
        
        // Validate metadata
        errors.append(contentsOf: validateMetadata(spec: spec))
        
        // Validate nodes
        errors.append(contentsOf: validateNodes(spec: spec))
        warnings.append(contentsOf: validateNodeWarnings(spec: spec))
        
        // Validate services
        errors.append(contentsOf: validateServices(spec: spec))
        
        // Validate overrides
        errors.append(contentsOf: validateOverrides(spec: spec))
        
        // Validate network settings
        warnings.append(contentsOf: validateNetwork(spec: spec))
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    private func validateMetadata(spec: ClusterSpec) -> [String] {
        var errors: [String] = []
        
        if spec.metadata.clusterName.isEmpty {
            errors.append("metadata.cluster_name is required and cannot be empty")
        }
        
        if let gatewayDomain = spec.metadata.gatewayDomain, gatewayDomain.isEmpty {
            errors.append("metadata.gateway_domain cannot be empty")
        }
        
        // Warning if acme_email is missing
        if spec.metadata.acmeEmail == nil || spec.metadata.acmeEmail?.isEmpty == true {
            // This is just a warning, not an error
        }
        
        return errors
    }
    
    private func validateNodes(spec: ClusterSpec) -> [String] {
        var errors: [String] = []
        var nodeNames: Set<String> = []
        var nodeIPs: Set<String> = []
        
        for node in spec.nodes ?? [] {
            // Check for duplicate names
            if nodeNames.contains(node.name) {
                errors.append("Duplicate node name: \(node.name)")
            }
            nodeNames.insert(node.name)
            
            // Check for duplicate IPs
            if nodeIPs.contains(node.ip) {
                errors.append("Duplicate node IP: \(node.ip)")
            }
            nodeIPs.insert(node.ip)
            
            // Validate IP format (basic check)
            if !isValidIP(node.ip) {
                errors.append("Node \(node.name) has invalid IP address: \(node.ip)")
            }
            
            // Validate roles
            if node.roles.isEmpty {
                errors.append("Node \(node.name) must have at least one role")
            }
            
            // Validate management IP format
            if let addresses = node.addresses,
               let managementIP = addresses["management_ip"],
               !isValidIP(managementIP) {
                errors.append("Node \(node.name) has invalid management_ip: \(managementIP)")
            }
            
            // Validate ansible_host format
            if let addresses = node.addresses,
               let ansibleHost = addresses["ansible_host"],
               !isValidIP(ansibleHost) {
                errors.append("Node \(node.name) has invalid ansible_host: \(ansibleHost)")
            }
        }
        
        return errors
    }
    
    private func validateNodeWarnings(spec: ClusterSpec) -> [String] {
        var warnings: [String] = []
        
        // Warn if control-plane node also has etcd role
        for node in spec.nodes ?? [] {
            if node.roles.contains("control-plane") && node.roles.contains("etcd") {
                warnings.append("Node \(node.name) has both control-plane and etcd roles (valid but consider separating)")
            }
        }
        
        return warnings
    }
    
    private func validateServices(spec: ClusterSpec) -> [String] {
        var errors: [String] = []
        var serviceNames: Set<String> = []
        
        for service in spec.services ?? [] {
            if serviceNames.contains(service.name) {
                errors.append("Duplicate service name: \(service.name)")
            }
            serviceNames.insert(service.name)
        }
        
        return errors
    }
    
    private func validateOverrides(spec: ClusterSpec) -> [String] {
        var errors: [String] = []
        
        if let overrides = spec.overrides {
            // Validate repo URL format if provided
            if let repo = overrides.repo, !repo.isEmpty {
                if !repo.hasPrefix("http://") && !repo.hasPrefix("https://") && !repo.hasPrefix("git@") {
                    errors.append("overrides.repo must be a valid URL, got: \(repo)")
                }
            }
        }
        
        return errors
    }
    
    private func validateNetwork(spec: ClusterSpec) -> [String] {
        var warnings: [String] = []
        
        if let network = spec.network {
            if let vlan = network.ovnExternalVlan {
                if vlan.vlanId != nil && vlan.vlanId! < 1 || vlan.vlanId! > 4094 {
                    warnings.append("OVN external VLAN ID \(vlan.vlanId!) is outside standard range (1-4094)")
                }
            }
        }
        
        return warnings
    }
    
    private func isValidIP(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        if parts.count != 4 { return false }
        
        for part in parts {
            if let num = Int(part), num >= 0 && num <= 255 {
                continue
            }
            return false
        }
        
        return true
    }
}
