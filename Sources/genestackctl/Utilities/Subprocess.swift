import Foundation

protocol ProcessRunnerProtocol {
    func run(executable: String, arguments: [String], environment: [String: String]) throws -> Bool
}

class ProcessRunner: ProcessRunnerProtocol {
    func run(executable: String, arguments: [String], environment: [String: String]) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        return process.terminationStatus == 0
    }
}
