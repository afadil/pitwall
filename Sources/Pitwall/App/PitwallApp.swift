import PitwallCore
import AppKit
import SwiftUI

@main
struct PitwallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("Pitwall", id: "main") {
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
        .accessibilityLabel(count > 0 ? "Pitwall, \(count) waiting on you" : "Pitwall")
    }
}
