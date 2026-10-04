import Foundation

/// Runs the `gh` CLI. The only way this app talks to GitHub; tests substitute a fake.
public protocol GHRunning: Sendable {
    func run(_ arguments: [String]) async throws -> ProcessResult
}

public enum GHError: Error, Sendable, Hashable, CustomStringConvertible {
    case notInstalled
    case notSignedIn
    case timedOut
    case failed(exitCode: Int32, message: String)
    case unreadableOutput(String)

    public var description: String {
        switch self {
        case .notInstalled: "gh not found. Install it with `brew install gh`."
        case .notSignedIn: "gh is signed out. Run `gh auth login` in Terminal."
        case .timedOut: "gh timed out"
        case .failed(_, let message): message.isEmpty ? "gh failed" : message
        case .unreadableOutput(let reason): "Can't read gh output: \(reason)"
        }
    }
}

/// The real `gh`, found in the usual install locations.
public struct GHCLI: GHRunning {
    public var executable: URL?

    public init(executable: URL? = ProcessRunner.locate("gh")) {
        self.executable = executable
    }

    public func run(_ arguments: [String]) async throws -> ProcessResult {
        guard let executable else { throw GHError.notInstalled }
        do {
            return try await ProcessRunner.run(
                executable: executable,
                arguments: arguments,
                environment: [
                    "GH_PROMPT_DISABLED": "1",
                    "GH_NO_UPDATE_NOTIFIER": "1",
                    "GH_SPINNER_DISABLED": "1",
                    "NO_COLOR": "1",
                    "CLICOLOR": "0",
                ],
                timeout: .seconds(30)
            )
        } catch ProcessRunnerError.timedOut {
            throw GHError.timedOut
        } catch let ProcessRunnerError.launchFailed(message) {
            throw GHError.failed(exitCode: -1, message: message)
        }
    }
}

extension GHError {
    /// Classifies a non-zero `gh` exit. gh exits 4 when authentication is required.
    static func from(_ result: ProcessResult) -> GHError {
        let message = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = message.lowercased()
        if result.exitCode == 4 || lowered.contains("gh auth login") || lowered.contains("not logged in") {
            return .notSignedIn
        }
        let firstLine = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return .failed(exitCode: result.exitCode, message: firstLine)
    }
}
