import Foundation

struct ShellResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ShellError: Error {
    case timeout
}

struct ShellExecutor {
    static let defaultTimeout: TimeInterval = 30

    private static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let supplemental = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin"
        if let existing = env["PATH"], !existing.isEmpty {
            env["PATH"] = supplemental + ":" + existing
        } else {
            env["PATH"] = supplemental + ":/usr/bin:/bin:/usr/sbin:/sbin"
        }
        return env
    }

    static func run(_ args: [String], at directory: String? = nil, timeout: TimeInterval = defaultTimeout) async -> ShellResult {
        await run("git", args, at: directory, timeout: timeout)
    }

    static func run(_ binary: String, _ args: [String], at directory: String? = nil, timeout: TimeInterval = defaultTimeout) async -> ShellResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [binary] + args
            process.environment = Self.augmentedEnvironment()

            if let dir = directory, !dir.isEmpty {
                process.currentDirectoryURL = URL(fileURLWithPath: dir)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Collect pipe data asynchronously to avoid blocking
            var stdoutData = Data()
            var stderrData = Data()
            let group = DispatchGroup()

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

            do {
                try process.run()
            } catch {
                // Drain pipes so the group completes
                try? stdoutPipe.fileHandleForReading.close()
                try? stderrPipe.fileHandleForReading.close()
                group.wait()
                continuation.resume(returning: ShellResult(stdout: "", stderr: error.localizedDescription, exitCode: -1))
                return
            }

            // Timeout watchdog
            let timeoutItem = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            process.terminationHandler = { terminatedProcess in
                timeoutItem.cancel()
                group.wait()

                let timedOut = terminatedProcess.terminationReason == .uncaughtSignal && terminatedProcess.terminationStatus == SIGTERM
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr: String
                if timedOut {
                    stderr = "Process timed out after \(Int(timeout))s"
                } else {
                    stderr = String(data: stderrData, encoding: .utf8) ?? ""
                }

                continuation.resume(returning: ShellResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: timedOut ? -1 : terminatedProcess.terminationStatus
                ))
            }
        }
    }
}
