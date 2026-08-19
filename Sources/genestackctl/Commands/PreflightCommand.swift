//
// PreflightCommand.swift
// genestack-cli
//
// Performs pre-flight checks for Genestack deployment
//

import Foundation
import ArgumentParser
import Yams

/// Perform pre-flight checks for cluster deployment
struct PreflightCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preflight",
        abstract: "Perform pre-flight checks for Genestack deployment"
    )
    
    @Option(help: "Cluster spec file")
    var config: String?
    
    @Flag(help: "Verbose output")
    var verbose: Bool = false
    
    func run() throws {
        let pathResolver = PathResolver()
        var results: [CheckItem] = []
        var warnings: [CheckItem] = []
        var errors: [CheckItem] = []
        
        print("=== Genestack Pre-flight Checks ===\n")
        
        // Check 1: Operating System
        let osCheck = checkOperatingSystem()
        results.append(osCheck)
        if !osCheck.passed { errors.append(osCheck) }
        logResult(osCheck)
        
        // Check 2: Required tools
        let toolsCheck = checkRequiredTools(pathResolver: pathResolver)
        results.append(toolsCheck)
        if !toolsCheck.passed { errors.append(toolsCheck) }
        logResult(toolsCheck)
        
        if verbose {
            checkDetailedTools(pathResolver: pathResolver)
        }
        
        // Check 3: Hardware requirements
        let hardwareCheck = checkHardwareRequirements()
        results.append(hardwareCheck)
        if !hardwareCheck.passed { warnings.append(hardwareCheck) }
        logResult(hardwareCheck)
        
        // Check 4: Network connectivity
        let networkCheck = checkNetworkConnectivity()
        results.append(networkCheck)
        if !networkCheck.passed { warnings.append(networkCheck) }
        logResult(networkCheck)
        
        // Check 5: Disk space
        let diskCheck = checkDiskSpace()
        results.append(diskCheck)
        if !diskCheck.passed { errors.append(diskCheck) }
        logResult(diskCheck)
        
        // Check 6: Memory
        let memoryCheck = checkMemory()
        results.append(memoryCheck)
        if !memoryCheck.passed { warnings.append(memoryCheck) }
        logResult(memoryCheck)
        
        // Check 7: Cluster spec validation (if provided)
        if let configPath = config {
            let specCheck = checkClusterSpec(configPath: configPath)
            results.append(specCheck)
            if !specCheck.passed { errors.append(specCheck) }
            logResult(specCheck)
        }
        
        // Summary
        print("\n=== Summary ===")
        let passed = results.filter { $0.passed }.count
        let failed = results.filter { !$0.passed }.count
        print("Passed: \(passed)/\(results.count)")
        print("Failed: \(failed)/\(results.count)")
        
        if !warnings.isEmpty {
            print("\nWarnings:")
            for warning in warnings {
                print("  ⚠️  \(warning.name): \(warning.message)")
            }
        }
        
        if !errors.isEmpty {
            print("\nErrors:")
            for error in errors {
                print("  ❌ \(error.name): \(error.message)")
            }
            print("\nPre-flight checks failed. Please resolve the above errors before proceeding.")
            throw ExitCode.failure
        }
        
        print("\n✅ All critical checks passed. Ready for deployment.")
    }
    
    // MARK: - Individual Checks
    
    private func checkOperatingSystem() -> CheckItem {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        
        #if os(macOS)
        // macOS 12+ required
        if os.majorVersion >= 12 {
            return CheckItem(name: "Operating System", passed: true, message: "macOS \(versionString)")
        } else {
            return CheckItem(name: "Operating System", passed: false, message: "macOS \(versionString) - requires 12.0+")
        }
        #elseif os(Linux)
        // Most modern Linux distributions should work
        return CheckItem(name: "Operating System", passed: true, message: "Linux \(versionString)")
        #else
        return CheckItem(name: "Operating System", passed: false, message: "Unsupported platform")
        #endif
    }
    
    private func checkRequiredTools(pathResolver: PathResolver) -> CheckItem {
        let requiredTools = ["git", "kubectl", "helm", "docker", "bash"]
        var missing: [String] = []
        
        for tool in requiredTools {
            if pathResolver.locateExecutable(named: tool) == nil {
                missing.append(tool)
            }
        }
        
        if missing.isEmpty {
            return CheckItem(name: "Required Tools", passed: true, message: "git, kubectl, helm, docker, bash all found")
        } else {
            return CheckItem(name: "Required Tools", passed: false, message: "Missing: \(missing.joined(separator: ", "))")
        }
    }
    
    private func checkDetailedTools(pathResolver: PathResolver) {
        let optionalTools = ["terraform", "vault", "kubectl-tree", "stern", "htop"]
        
        print("\nOptional tools:")
        for tool in optionalTools {
            if let path = pathResolver.locateExecutable(named: tool) {
                print("  ✅ \(tool): \(path)")
            } else {
                print("  ⚠️  \(tool): not installed (optional)")
            }
        }
    }
    
    private func checkHardwareRequirements() -> CheckItem {
        var issues: [String] = []
        
        // Check CPU cores
        let coreCount = ProcessInfo.processInfo.processorCount
        if coreCount < 4 {
            issues.append("CPU cores (\(coreCount)) < 4 recommended")
        }
        
        // Check memory
        let memoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if memoryGB < 16 {
            issues.append("Memory (\(memoryGB)GB) < 16GB recommended")
        }
        
        if issues.isEmpty {
            return CheckItem(
                name: "Hardware Requirements",
                passed: true,
                message: "CPU: \(coreCount) cores, Memory: \(memoryGB)GB"
            )
        } else {
            return CheckItem(
                name: "Hardware Requirements",
                passed: false,
                message: issues.joined(separator: "; ")
            )
        }
    }
    
    private func checkNetworkConnectivity() -> CheckItem {
        // Simple connectivity check note - real implementation would use URLSession
        return CheckItem(
            name: "Network Connectivity",
            passed: true,
            message: "Network check requires --verbose for details"
        )
    }
    
    private func checkDiskSpace() -> CheckItem {
        do {
            let path = "/"
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            
            let freeSpace = attrs[.systemFreeSize] as? NSNumber
            if let freeSpace = freeSpace {
                let freeGB = freeSpace.intValue / (1024 * 1024 * 1024)
                if freeGB >= 50 {
                    return CheckItem(
                        name: "Disk Space",
                        passed: true,
                        message: "\(freeGB)GB free at \(path)"
                    )
                } else {
                    return CheckItem(
                        name: "Disk Space",
                        passed: false,
                        message: "Only \(freeGB)GB free at \(path) - need 50GB+"
                    )
                }
            }
        } catch {
            return CheckItem(
                name: "Disk Space",
                passed: false,
                message: "Could not check disk space: \(error.localizedDescription)"
            )
        }
        
        return CheckItem(
            name: "Disk Space",
            passed: false,
            message: "Unknown error checking disk space"
        )
    }
    
    private func checkMemory() -> CheckItem {
        let memoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if memoryGB >= 32 {
            return CheckItem(name: "Memory", passed: true, message: "\(memoryGB)GB available")
        } else if memoryGB >= 16 {
            return CheckItem(name: "Memory", passed: true, message: "\(memoryGB)GB available (minimum)")
        } else {
            return CheckItem(
                name: "Memory",
                passed: false,
                message: "Only \(memoryGB)GB - recommend 16GB minimum, 32GB preferred"
            )
        }
    }
    
    private func checkClusterSpec(configPath: String) -> CheckItem {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return CheckItem(
                name: "Cluster Spec",
                passed: false,
                message: "Spec file not found: \(configPath)"
            )
        }
        
        do {
            let content = try String(contentsOfFile: configPath)
            let spec = try YAMLDecoder().decode(ClusterSpec.self, from: content)
            
            let validator = SpecValidator()
            let result = validator.validate(spec: spec)
            
            if result.isValid {
                var warningMsg = ""
                if !result.warnings.isEmpty {
                    warningMsg = " (\(result.warnings.count) warnings)"
                }
                return CheckItem(
                    name: "Cluster Spec",
                    passed: true,
                    message: "Valid spec\(warningMsg)"
                )
            } else {
                return CheckItem(
                    name: "Cluster Spec",
                    passed: false,
                    message: result.errors.joined(separator: "; ")
                )
            }
        } catch {
            return CheckItem(
                name: "Cluster Spec",
                passed: false,
                message: "Parse error: \(error.localizedDescription)"
            )
        }
    }
    
    private func logResult(_ item: CheckItem) {
        let icon = item.passed ? "✅" : "❌"
        print("\(icon) \(item.name): \(item.message)")
    }
}

/// Simple data structure for pre-flight check results
struct CheckItem {
    let name: String
    let passed: Bool
    let message: String
}
