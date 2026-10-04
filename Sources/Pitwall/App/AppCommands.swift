import PitwallCore
import AppKit
import SwiftUI

/// Menu bar commands, so everything is reachable from the keyboard.
struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = registerOpenWindow()
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { show(.settings) }
                .keyboardShortcut(",")
        }
        CommandGroup(after: .toolbar) {
            Button("Board") { show(.board) }
                .keyboardShortcut("1")
            Button("Overview") { show(.overview) }
                .keyboardShortcut("2")
            Divider()
            Button(model.inspectorOpen ? "Hide details" : "Show details") {
                if model.selectedTaskID == nil { model.select(model.visibleBoard.tasks.first) }
                model.inspectorOpen.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Toggle("Show hidden cards", isOn: Binding(get: { model.settings.showHidden }, set: { model.settings.showHidden = $0 }))
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Toggle("Show archived sessions", isOn: Binding(get: { model.settings.showArchived }, set: { model.settings.showArchived = $0 }))
            Picker("Group by", selection: Binding(get: { model.settings.grouping }, set: { model.settings.grouping = $0 })) {
                ForEach(Grouping.allCases) { Text($0.title).tag($0) }
            }
            Divider()
            Button("Refresh") { Task { await model.refreshAll() } }
                .keyboardShortcut("r")
        }
        CommandMenu("Task") {
            let task = model.selectedTask
            Button("Open in \(task?.sessionToOpen?.app.displayName ?? "app")") { task.map { model.openInApp($0) } }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(task?.sessionToOpen?.appURL == nil)
            Button("Open pull request") { task.map(model.openPullRequest) }
                .keyboardShortcut("o")
                .disabled(task?.pullRequest?.url == nil)
            Button("Open folder") { task.map { model.openFolder($0) } }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(task?.directory == nil)
            Button("Copy resume command") {
                if let session = task?.onBranchSessions.first ?? task?.sessions.first { model.copyResumeCommand(session) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(task?.sessions.contains { $0.resumeCommand != nil } != true)
            Button("Copy branch name") { task.map(model.copyBranch) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(task?.branch == nil)
            Divider()
            Button("Mark ready for review…") { task.map { model.request(.markReady, for: $0) } }
                .disabled(!(task?.pullRequest.map { $0.state == .open && $0.isDraft } ?? false))
            Button("Merge…") { task.map { model.request(.merge(.squash), for: $0) } }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!(task?.pullRequest.map { $0.state == .open && !$0.isDraft } ?? false))
            Divider()
            ForEach(Lane.allCases) { lane in
                Button("Move to \(lane.title)") { task.map { model.setLane(lane, for: $0) } }
                    .keyboardShortcut(lane.shortcut, modifiers: .control)
                    .disabled(task == nil || task?.lane == lane)
            }
            Menu("Tags") {
                ForEach(model.organization.tags) { tag in
                    Toggle(tag.name, isOn: Binding(
                        get: { task.map { model.hasTag(tag, $0) } ?? false },
                        set: { on in task.map { model.setTag(tag, on: on, for: $0) } }
                    ))
                }
                if !model.organization.tags.isEmpty { Divider() }
                Button("New tag…") { model.beginNewTag(for: task) }
            }
            .disabled(task == nil)
            Divider()
            Button(task?.isHidden == true ? "Show card" : "Hide card") { task.map(model.toggleHidden) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(task == nil)
        }
    }

    private func registerOpenWindow() {
        let openWindow = openWindow
        model.openMainWindow = { openWindow(id: "main") }
    }

    private func show(_ screen: AppModel.Screen) {
        model.screen = screen
        openWindow(id: "main")
        NSApp.activate()
    }
}
