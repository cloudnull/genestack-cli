//
// PathResolver.swift
// genestack-cli
//
// Platform-aware path resolution for cross-platform compatibility
//

import Foundation

/// Detects the current platform and provides platform-specific configurations
enum Platform {
    case macOS
    case linux
    
    /// Detect the current operating system
    static var current: Platform {
        #if os(macOS)
        return .macOS
        #elseif os(Linux)
        return .linux
        #else
        return .linux
        #endif
    }
    
    /// The default Genestack installation directory for this platform
    var defaultGenestackDir: String {
        switch self {
        case .macOS:
            return "/opt/genestack"
        case .linux:
            return "/opt/genestack"
        }
    }
    
    /// The default overrides directory for this platform
    var defaultOverridesDir: String {
        switch self {
        case .macOS, .linux:
            return "/etc/genestack"
        }
    }
    
    /// Path to git executable
    var gitPath: String {
        // Use /usr/bin/git on macOS, which is more reliable
        switch self {
        case .macOS:
            return "/usr/bin/git"
        case .linux:
            return "/usr/bin/env git"  // Use PATH lookup on Linux
        }
    }
    
    /// Path to bash executable
    var bashPath: String {
        switch self {
        case .macOS:
            return "/bin/bash"
        case .linux:
            return "/bin/bash"  // Standard on most Linux distros
        }
    }
}

/// Provides cross-platform path resolution and executable discovery
class PathResolver {
    let platform: Platform
    private let genestackDir: String
    
    init(genestackDir: String? = nil, platform: Platform = .current) {
        self.platform = platform
        self.genestackDir = genestackDir ?? ProcessInfo.processInfo.environment["GENESTACK_BASE_DIR"] ?? platform.defaultGenestackDir
    }
    
    /// Resolve the full path for a relative path within the Genestack installation
    func resolvePath(for relativePath: String) -> String {
        return (genestackDir as NSString).appendingPathComponent(relativePath)
    }
    
    /// Locate an executable in PATH or at known locations
    func locateExecutable(named name: String) -> String? {
        #if os(macOS)
        let knownPaths = [
            "/usr/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/opt/genestack/bin/\(name)"
        ]
        #else
        let knownPaths = [
            "/usr/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/genestack/bin/\(name)"
        ]
        #endif
        
        for path in knownPaths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        
        // Try PATH lookup
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        whichProcess.arguments = ["which", name]
        
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            
            if whichProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    return output
                }
            }
        } catch {
            // Ignore and return nil
        }
        
        return nil
    }
    
    /// Get the services directory path
    var servicesDir: String {
        return resolvePath(for: "bin/services")
    }
    
    /// Get the install.sh path
    var installScriptPath: String {
        return resolvePath(for: "bin/install.sh")
    }
    
    /// Get the bootstrap.sh path
    var bootstrapScriptPath: String {
        return resolvePath(for: "bin/bootstrap.sh")
    }
    
    var path: String {
        return genestackDir
    }
}
