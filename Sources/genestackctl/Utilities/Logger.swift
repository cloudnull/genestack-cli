//
// Logger.swift
// genestack-cli
//
// Simple logging utility with progress indicators
//

import Foundation

/// Log level for filtering output
enum LogLevel: Int, CaseIterable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3
    case success = 4
    case none = 5
    
    var prefix: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        case .success: return "OK"
        case .none: return ""
        }
    }
    
    var emoji: String {
        switch self {
        case .debug: return "🔧"
        case .info: return "ℹ️"
        case .warn: return "⚠️"
        case .error: return "❌"
        case .success: return "✅"
        case .none: return ""
        }
    }
}

/// Simple logger with verbosity control
class Logger {
    private let verbose: Bool
    private let output: OutputDestination
    
    init(verbose: Bool = false, output: OutputDestination = .stdout) {
        self.verbose = verbose
        self.output = output
    }
    
    func debug(_ message: String) {
        if verbose {
            log(.debug, message)
        }
    }
    
    func info(_ message: String) {
        log(.info, message)
    }
    
    func warn(_ message: String) {
        log(.warn, message)
    }
    
    func error(_ message: String) {
        log(.error, message)
    }
    
    func success(_ message: String) {
        log(.success, message)
    }
    
    private func log(_ level: LogLevel, _ message: String) {
        let prefix: String
        if verbose {
            prefix = "[\(level.prefix)] \(level.emoji)"
        } else if level == .success || level == .warn || level == .error {
            prefix = level.emoji
        } else {
            prefix = ""
        }
        
        let outputMessage = prefix.isEmpty ? message : "\(prefix) \(message)"
        
        switch output {
        case .stdout:
            print(outputMessage)
        case .stderr:
            fputs(outputMessage + "\n", stderr)
        }
    }
}

enum OutputDestination {
    case stdout
    case stderr
}

/// Progress indicator for long-running operations
class ProgressIndicator {
    private let message: String
    private let verbose: Bool
    private var isAnimating = false
    private let spinnerChars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var animationTimer: Timer?
    private var spinnerIndex = 0
    
    init(message: String, verbose: Bool = false) {
        self.message = message
        self.verbose = verbose
    }
    
    func start() {
        if verbose {
            print(message + "...")
        }
    }
    
    func stop(success: Bool = true) {
        if !verbose {
            let result = success ? "✅" : "❌"
            print("\(result) \(message)")
        }
    }
}
