//
// GenestackError.swift
// genestack-cli
//
// Custom error types for the CLI
//

import Foundation

/// Errors specific to Genestack CLI operations
enum GenestackError: Error, LocalizedError, Equatable {
    case environmentError(String)
    case scriptNotFound(String)
    case scriptFailed(String, Int32)
    case serviceNotFound(String)
    case catalogLoadFailed(String)
    case specParseFailed(String)
    case specValidationFailed(String)
    case dependencyResolutionFailed(String)
    case k8sConnectionFailed(String)
    case secretNotFound(String)
    case gitOperationFailed(String)
    case fileOperationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .environmentError(let msg):
            return "Environment error: \(msg)"
        case .scriptNotFound(let script):
            return "Script not found: \(script)"
        case .scriptFailed(let script, let code):
            return "Script '\(script)' failed with exit code \(code)"
        case .serviceNotFound(let service):
            return "Service '\(service)' not found in catalog"
        case .catalogLoadFailed(let reason):
            return "Failed to load service catalog: \(reason)"
        case .specParseFailed(let reason):
            return "Failed to parse cluster spec: \(reason)"
        case .specValidationFailed(let reason):
            return "Cluster spec validation failed: \(reason)"
        case .dependencyResolutionFailed(let reason):
            return "Dependency resolution failed: \(reason)"
        case .k8sConnectionFailed(let reason):
            return "Kubernetes connection failed: \(reason)"
        case .secretNotFound(let secret):
            return "Secret '\(secret)' not found in Kubernetes"
        case .gitOperationFailed(let reason):
            return "Git operation failed: \(reason)"
        case .fileOperationFailed(let reason):
            return "File operation failed: \(reason)"
        }
    }
}
