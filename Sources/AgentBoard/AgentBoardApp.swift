import AgentBoardCore
import AppKit
import SwiftUI

@main
struct AgentBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("Agent Board", id: "main") {
            MainWindow()
                .environment(model)
                .tint(Theme.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1380, height: 860)
        .defaultLaunchBehavior(.presented)
        .commands { AppCommands(model: model) }

        MenuBarExtra(isInserted: Binding(
            get: { model.settings.showMenuBarExtra },
            // Assign only on change: the system sets this when it inserts the item,
            // and an unconditional write would re-trigger scene updates forever.
            set: { if model.settings.showMenuBarExtra != $0 { model.settings.showMenuBarExtra = $0 } }
        )) {
            MenuBarPanel()
                .environment(model)
                .tint(Theme.accent)
        } label: {
            MenuBarLabel(count: model.board.count(.waiting))
        }
        .menuBarExtraStyle(.window)
    }
}

extension AppModel {
    static let shared = AppModel()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let folder = LaunchOptions.current.renderIconDirectory {
            do { try IconArt.render(to: folder) } catch { print("icon: \(error)") }
            exit(0)
        }
        let model = AppModel.shared
        if model.mode.isSnapshotRun || model.mode.verbose { setvbuf(stdout, nil, _IONBF, 0) }
        model.mode.applyAppearance()
        model.start()
        if model.mode.isSnapshotRun {
            Task { await SnapshotRunner.run(model: model) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep counting in the menu bar after the window closes.
        !AppModel.shared.settings.showMenuBarExtra
    }
}

/// Menu bar item: the board glyph plus the number of tasks waiting on you.
struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        Group {
            if count > 0 {
                Text("\(Image(systemName: "rectangle.split.3x1.fill")) \(count)")
            } else {
                Image(systemName: "rectangle.split.3x1")
            }
        }
        .accessibilityLabel(count > 0 ? "Agent Board, \(count) waiting on you" : "Agent Board")
    }
}

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
