import Foundation

public struct ProcessResult: Sendable, Hashable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data

    public init(exitCode: Int32, stdout: Data = Data(), stderr: Data = Data()) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

public enum ProcessRunnerError: Error, Sendable, Equatable {
    case launchFailed(String)
    case timedOut
}

/// Runs a command-line tool and collects its output, with a timeout.
public enum ProcessRunner {
    public static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String] = [:],
        timeout: Duration = .seconds(30)
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        var env = ProcessInfo.processInfo.environment
        env.merge(environment) { _, new in new }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        // Drain pipes concurrently so a chatty process can't fill the buffer and stall.
        let outBox = DataBox()
        let errBox = DataBox()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { outBox.append(chunk) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { errBox.append(chunk) }
        }

        let exit: Int32 = try await withThrowingTaskGroup(of: Int32?.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { finished in
                        continuation.resume(returning: finished.terminationStatus)
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let code = first else {
                if process.isRunning { process.terminate() }
                throw ProcessRunnerError.timedOut
            }
            return code
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        if let rest = try? stdout.fileHandleForReading.readToEnd() { outBox.append(rest) }
        if let rest = try? stderr.fileHandleForReading.readToEnd() { errBox.append(rest) }
        return ProcessResult(exitCode: exit, stdout: outBox.data, stderr: errBox.data)
    }

    /// First executable named `name` in the usual places. GUI apps don't inherit
    /// the shell's PATH, so Homebrew locations are checked explicitly.
    public static func locate(_ name: String, extraDirectories: [String] = []) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories =
            extraDirectories + ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/bin", "/usr/bin", "/bin"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories += path.split(separator: ":").map(String.init)
        }
        var seen = Set<String>()
        for directory in directories where seen.insert(directory).inserted {
            let candidate = URL(filePath: directory).appending(path: name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
