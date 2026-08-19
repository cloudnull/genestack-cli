//
// OverridesManager.swift
// genestack-cli
//
// Manages per-cluster overrides repository cloning
//

import Foundation

/// Manages cloning and applying per-cluster overrides repositories
class OverridesManager {
    private let genestackDir: String
    private let processRunner: ProcessRunnerProtocol
    
    init(genestackDir: String?, processRunner: ProcessRunnerProtocol = ProcessRunner()) {
        self.genestackDir = genestackDir ?? ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? "/opt/genestack"
        self.processRunner = processRunner
    }
    
    /// Determine the correct overrides directory based on spec
    /// - Parameters:
    ///   - spec: Overrides specification
    ///   - defaultDir: Default overrides directory (usually /etc/genestack)
    /// - Returns: The resolved overrides directory path
    func resolveOverridesDir(spec: OverridesSpec?, defaultDir: String) -> String {
        if let spec = spec, spec.replaceBase == true {
            return genestackDir
        }
        return defaultDir
    }
    
    /// Clone the overrides repository
    /// - Parameters:
    ///   - spec: Overrides specification with repo URL and ref
    ///   - to: Target directory to clone into
    ///   - dryRun: If true, don't actually clone
    /// - Throws: Error if clone fails
    func cloneOverridesRepo(spec: OverridesSpec, to: String, dryRun: Bool = false) throws {
        guard let repo = spec.repo, !repo.isEmpty else {
            return
        }
        
        let ref = spec.ref ?? "main"
        
        // Ensure target directory's parent exists
        let parentDir = (to as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: parentDir) {
            if !dryRun {
                try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            }
        }
        
        if dryRun {
            print("[Dry run] Would clone \(repo) to \(to)")
            return
        }
        
        // Remove existing directory if present
        if FileManager.default.fileExists(atPath: to) {
            try FileManager.default.removeItem(atPath: to)
        }
        
        // Clone repository
        let gitArgs = [
            "clone",
            "--depth", "1",
            "-b", ref,
            repo,
            to
        ]
        
        let result = try processRunner.run(
            executable: "/usr/bin/git",
            arguments: gitArgs,
            environment: ProcessInfo.processInfo.environment
        )
        
        if !result.success {
            throw GenestackError.gitOperationFailed("Failed to clone overrides repository: \(repo)")
        }
    }
    
    /// Clone the overrides repository to the default overrides directory
    /// - Parameters:
    ///   - spec: Cluster specification containing overrides config
    ///   - dryRun: If true, don't actually clone
    /// - Throws: Error if clone fails
    /// - Returns: The overrides directory path
    @discardableResult
    func setupOverrides(spec: ClusterSpec, dryRun: Bool = false) throws -> String {
        let defaultOverridesDir = "/etc/genestack"
        let overridesDir = resolveOverridesDir(spec: spec.overrides, defaultDir: defaultOverridesDir)
        
        if let overrides = spec.overrides, overrides.repo != nil {
            try cloneOverridesRepo(spec: overrides, to: overridesDir, dryRun: dryRun)
        }
        
        return overridesDir
    }
}
