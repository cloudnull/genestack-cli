//
// FailureHandler.swift
// genestack-cli
//
// Handles pipeline failures based on configured modes
//

import Foundation

/// Handles failures during pipeline execution based on the configured mode
class FailureHandler {
    
    /// Handle a service installation failure
    /// - Parameters:
    ///   - service: The service that failed
    ///   - error: The error that occurred
    ///   - mode: The failure handling mode
    /// - Returns: true if execution should continue, false to stop
    static func handle(service: String, error: Error, mode: FailureMode) -> Bool {
        switch mode {
        case .failFast:
            print("ERROR: Service '\(service)' failed - aborting due to fail-fast mode")
            print("Error: \(error.localizedDescription)")
            return false
            
        case .continueOnFailure:
            print("WARNING: Service '\(service)' failed - continuing with remaining services")
            print("Error: \(error.localizedDescription)")
            return true
            
        case .prompt:
            print("Service '\(service)' failed!")
            print("Error: \(error.localizedDescription)")
            print("Options: retry (r), skip (s), abort (a): ", terminator: "")
            
            if let input = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) {
                switch input {
                case "r", "retry":
                    return true // Caller should retry
                case "s", "skip":
                    return true // Skip this service
                case "a", "abort":
                    return false // Abort pipeline
                default:
                    print("Invalid option. Aborting.")
                    return false
                }
            }
            return false
        }
    }
    
    /// Handle a generic pipeline error
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - mode: The failure handling mode
    /// - Returns: true if execution should continue, false to stop
    static func handle(error: Error, mode: FailureMode) -> Bool {
        return handle(service: "unknown", error: error, mode: mode)
    }
}
