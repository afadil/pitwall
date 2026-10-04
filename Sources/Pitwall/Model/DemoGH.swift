import PitwallCore
import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Answers `gh` in demo mode so demo screens never touch GitHub.
struct DemoGH: GHRunning {
    func run(_ arguments: [String]) async throws -> ProcessResult {
        if arguments.first == "repo" {
            return ProcessResult(exitCode: 0, stdout: Data(#"{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":false}"#.utf8))
        }
        // Writes "succeed" without doing anything.
        try await Task.sleep(for: .milliseconds(400))
        return ProcessResult(exitCode: 0)
    }
}
