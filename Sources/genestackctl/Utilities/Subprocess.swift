//
// Subprocess.swift
// genestack-cli
//
// Executes external processes and captures output
//

import Foundation

/// Protocol for running subprocess commands
protocol ProcessRunnerProtocol {
    func run(executable: String, arguments: [String], environment: [String: String]) throws -> ProcessResult
}

/// Result of a process execution
struct ProcessResult {
    let success: Bool
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Default implementation using Foundation.Process
class ProcessRunner: ProcessRunnerProtocol {
    func run(executable: String, arguments: [String], environment: [String: String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GenestackError.fileOperationFailed("Failed to execute \(executable): \(error.localizedDescription)")
        }
        
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        
        return ProcessResult(
            success: process.terminationStatus == 0,
            stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: process.terminationStatus
        )
    }
}

/// Mock implementation for testing
class MockProcessRunner: ProcessRunnerProtocol {
    var results: [ProcessResult] = []
    var resultIndex = 0
    
    func addResult(_ result: ProcessResult) {
        results.append(result)
    }
    
    func run(executable: String, arguments: [String], environment: [String: String]) throws -> ProcessResult {
        guard resultIndex < results.count else {
            return ProcessResult(success: true, stdout: "", stderr: "", exitCode: 0)
        }
        let result = results[resultIndex]
        resultIndex += 1
        return result
    }
}
