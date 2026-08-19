//
// EnvironmentManager.swift
// genestack-cli
//
// Manages environment variables for Genestack installation
//

import Foundation

/// Manages Genestack environment variables
class EnvironmentManager {
    private let genestackDir: String
    
    /// Initialize with an optional override directory
    /// - Parameter genestackDir: Override path for GENESTACK_BASE_DIR (defaults to env var or /opt/genestack)
    init(genestackDir: String?) {
        self.genestackDir = genestackDir ?? ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
    }
    
    /// Generate the environment variables dictionary from a cluster spec
    /// - Parameters:
    ///   - spec: Cluster specification
    ///   - overridesDir: Directory where overrides will be cloned
    /// - Returns: Dictionary of environment variables
    func generateEnvironment(spec: ClusterSpec, overridesDir: String) -> [String: String] {
        var env: [String: String] = [:]
        
        // Determine the actual overrides directory based on replace_base
        let actualOverridesDir: String
        if spec.overrides?.replaceBase == true {
            actualOverridesDir = genestackDir
            // When replace_base is true, GENESTACK_BASE_DIR becomes the overrides dir
            env["GENESTACK_BASE_DIR"] = overridesDir
        } else {
            actualOverridesDir = overridesDir
            env["GENESTACK_BASE_DIR"] = genestackDir
        }
        
        env["GENESTACK_OVERRIDES_DIR"] = actualOverridesDir
        env["GENESTACK_SERVICES_DIR"] = "\(genestackDir)/bin/services"
        env["GENESTACK_COMPONENTS_FILE"] = "\(actualOverridesDir)/openstack-components.yaml"
        
        // Add environment vars from spec
        if let environment = spec.environment {
            for (key, value) in environment {
                env[key] = value
            }
        }
        
        return env
    }
    
    /// Merge environment with current process environment
    /// - Parameters:
    ///   - spec: Cluster specification
    ///   - overridesDir: Directory where overrides will be cloned
    /// - Returns: Complete environment dictionary for subprocess execution
    func getFullEnvironment(spec: ClusterSpec, overridesDir: String) -> [String: String] {
        var baseEnv = ProcessInfo.processInfo.environment
        let specEnv = generateEnvironment(spec: spec, overridesDir: overridesDir)
        
        // Merge with priority to spec-defined values
        for (key, value) in specEnv {
            baseEnv[key] = value
        }
        
        return baseEnv
    }
}
