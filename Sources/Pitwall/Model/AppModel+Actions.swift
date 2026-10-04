import AppKit
import PitwallCore
import SwiftUI

/// Things you do to a card: open it, copy from it, and the GitHub writes.
extension AppModel {
    func select(_ task: BoardTask?) {
        selectedTaskID = task?.id
    }

    func openPullRequest(_ task: BoardTask) {
        guard let url = task.pullRequest?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func openFolder(_ task: BoardTask, with opener: FolderOpener? = nil) {
        guard let path = task.directory else { return }
        let url = URL(filePath: path, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: path) else {
            show(.failure, "That folder no longer exists")
            return
        }
        switch opener ?? settings.folderOpener {
        case .finder:
            NSWorkspace.shared.open(url)
        case .terminal:
            open(url, withApp: URL(filePath: "/System/Applications/Utilities/Terminal.app"))
        case .editor:
            if let editor = Self.editorURL {
                open(url, withApp: editor)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func open(_ url: URL, withApp app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The app that opens source code by default, used as "the default editor".
    static var editorURL: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: .sourceCode)
            ?? NSWorkspace.shared.urlForApplication(toOpen: .plainText)
    }

    static var editorName: String {
        editorURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? "Editor"
    }

    /// Opens the session in the Claude or Codex app through its deep link.
    func openInApp(_ session: AgentSession) {
        guard let url = session.appURL else { return }
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            show(.failure, "\(session.app.displayName) isn't installed")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openInApp(_ task: BoardTask) {
        guard let session = task.sessionToOpen else { return }
        openInApp(session)
    }

    func copyResumeCommand(_ session: AgentSession) {
        guard let command = session.resumeCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        show(.success, "Copied \(session.app.displayName) resume command")
    }

    func copyBranch(_ task: BoardTask) {
        guard let branch = task.branch else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(branch, forType: .string)
        show(.success, "Copied branch name")
    }

    func request(_ action: PRWriteAction, for task: BoardTask) {
        guard let pr = task.pullRequest else { return }
        Task {
            await writes.request(action, for: pr)
            if case .failed(let message) = writes.lastOutcome {
                show(.failure, message)
                writes.clearOutcome()
            }
        }
    }

    func confirmWrite() {
        Task {
            await writes.confirm()
            switch writes.lastOutcome {
            case .succeeded(let message): show(.success, message)
            case .failed(let message): show(.failure, message)
            case nil: break
            }
            writes.clearOutcome()
        }
    }
}
