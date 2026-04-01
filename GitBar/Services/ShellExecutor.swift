import Foundation

struct ShellResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

struct ShellExecutor {
    static func run(_ args: [String], at directory: String? = nil) -> ShellResult {
        run("git", args, at: directory)
    }

    static func run(_ binary: String, _ args: [String], at directory: String? = nil) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [binary] + args

        if let dir = directory, !dir.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdoutData = Data()
        var stderrData = Data()
        let group = DispatchGroup()

        do {
            try process.run()
        } catch {
            return ShellResult(stdout: "", stderr: error.localizedDescription, exitCode: -1)
        }

        group.enter()
        DispatchQueue.global().async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return ShellResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
