import PitwallCore
import SwiftUI

/// Context menu for a task. Also used by Done rows and the inspector's "More" menu.
struct TaskActionsMenu: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask

    var body: some View {
        let openable = task.sessions.filter { $0.appURL != nil }
        if openable.count == 1, let session = openable.first {
            Button("Open in \(session.app.displayName)", systemImage: "arrow.up.forward.app") { model.openInApp(session) }
        } else if openable.count > 1 {
            ForEach(openable) { session in
                Button("Open in \(session.app.displayName): \(session.title)", systemImage: "arrow.up.forward.app") { model.openInApp(session) }
            }
        }
        if task.pullRequest?.url != nil {
            Button("Open pull request", systemImage: "arrow.up.right.square") { model.openPullRequest(task) }
        }
        if task.directory != nil {
            Menu("Open folder", systemImage: "folder") {
                Button("In Finder") { model.openFolder(task, with: .finder) }
                Button("In Terminal") { model.openFolder(task, with: .terminal) }
                Button("In \(AppModel.editorName)") { model.openFolder(task, with: .editor) }
            }
        }
        let resumable = task.sessions.filter { $0.resumeCommand != nil }
        if resumable.count == 1, let session = resumable.first {
            Button("Copy resume command", systemImage: "terminal") { model.copyResumeCommand(session) }
        } else if resumable.count > 1 {
            Menu("Copy resume command", systemImage: "terminal") {
                ForEach(resumable) { session in
                    Button("\(session.app.displayName): \(session.title)") { model.copyResumeCommand(session) }
                }
            }
        }
        if task.branch != nil {
            Button("Copy branch name", systemImage: "doc.on.doc") { model.copyBranch(task) }
        }
        Divider()
        OrganizeMenu(task: task)
        if let pr = task.pullRequest, pr.state == .open {
            Divider()
            if pr.isDraft {
                Button("Mark ready for review…", systemImage: "eye") { model.request(.markReady, for: task) }
            } else {
                Button("Merge…", systemImage: "arrow.trianglehead.merge") { model.request(.merge(.squash), for: task) }
            }
        }
        Divider()
        Button(task.isHidden ? "Show card" : "Hide card", systemImage: task.isHidden ? "eye" : "eye.slash") {
            model.toggleHidden(task)
        }
    }
}

/// VoiceOver custom actions mirroring the context menu.
struct TaskAccessibilityActions: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask

    var body: some View {
        if let session = task.sessionToOpen, session.appURL != nil {
            Button("Open in \(session.app.displayName)") { model.openInApp(session) }
        }
        if task.pullRequest?.url != nil {
            Button("Open pull request") { model.openPullRequest(task) }
        }
        if let session = task.sessions.first(where: { $0.resumeCommand != nil }) {
            Button("Copy resume command") { model.copyResumeCommand(session) }
        }
        if task.directory != nil {
            Button("Open folder") { model.openFolder(task) }
        }
        if let pr = task.pullRequest, pr.state == .open {
            if pr.isDraft {
                Button("Mark ready for review") { model.request(.markReady, for: task) }
            } else {
                Button("Merge") { model.request(.merge(.squash), for: task) }
            }
        }
        ForEach(Lane.allCases.filter { $0 != task.lane }) { lane in
            Button("Move to \(lane.title)") { model.setLane(lane, for: task) }
        }
        Button(task.isHidden ? "Show card" : "Hide card") { model.toggleHidden(task) }
    }
}

/// "Lane" and "Tags" submenus for a card's context menu.
struct OrganizeMenu: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask

    var body: some View {
        Menu("Lane", systemImage: "rectangle.grid.1x2") {
            Picker("Lane", selection: Binding(get: { task.lane }, set: { model.setLane($0, for: task) })) {
                ForEach(Lane.allCases) { lane in
                    Label(lane.title, systemImage: lane.symbol).tag(lane)
                }
            }
            .pickerStyle(.inline)
        }
        Menu("Tags", systemImage: "tag") {
            ForEach(model.organization.tags) { tag in
                Toggle(isOn: Binding(get: { model.hasTag(tag, task) }, set: { model.setTag(tag, on: $0, for: task) })) {
                    Label { Text(tag.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(tag.color.color) }
                }
            }
            if !model.organization.tags.isEmpty { Divider() }
            Button("New tag…") { model.beginNewTag(for: task) }
        }
    }
}
