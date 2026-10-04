import AgentBoardCore
import AppKit
import SwiftUI

/// `--snapshot-dir` support: shows each screen in turn, has `Scripts/snapshots.sh`
/// capture only this app's windows, then quits. A synthetic backdrop window sits
/// behind so translucency never shows anything else on screen.
@MainActor
enum SnapshotRunner {
    static func run(model: AppModel) async {
        guard let directory = model.mode.snapshotDirectory else { return }
        print("snapshot: starting, demo=\(model.mode.demo)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let prefix = model.mode.snapshotPrefix

        NSApp.activate()
        let backdrop = makeBackdrop()
        backdrop.orderFront(nil)

        // Wait for data (real runs also wait for gh), then for the main window.
        for _ in 0..<60 where !(model.hasLoaded && (model.mode.demo || model.github.fetchedAt != nil)) {
            try? await Task.sleep(for: .milliseconds(500))
        }
        var mainWindow: NSWindow?
        for attempt in 0..<40 {
            if attempt == 4 { model.openMainWindow?() }
            mainWindow = NSApp.windows.first { window in
                window !== backdrop && window.styleMask.contains(.titled) && window.isVisible
            }
            if mainWindow != nil { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        print("snapshot: windows=\(NSApp.windows.map { "\(type(of: $0))|\($0.title)|titled=\($0.styleMask.contains(.titled))|visible=\($0.isVisible)" })")
        guard let window = mainWindow, let screen = window.screen ?? NSScreen.main else {
            print("snapshot: main window not found")
            NSApp.terminate(nil)
            return
        }

        let size = NSSize(width: 1440, height: 900)
        let visible = screen.visibleFrame
        window.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height), display: true)
        window.makeKeyAndOrderFront(nil)
        backdrop.setFrame(window.frame.insetBy(dx: -60, dy: -60), display: true)
        backdrop.order(.below, relativeTo: window.windowNumber)

        func shoot(_ name: String, _ target: NSWindow) async {
            try? await Task.sleep(for: .milliseconds(1100))
            await capture(target, to: directory.appending(path: "\(prefix)-\(name).png"))
        }

        model.inspectorOpen = false
        model.selectedTaskID = nil
        model.screen = .board
        await shoot("board", window)

        let chosen = model.mode.snapshotSelect.flatMap { number in model.board.tasks.first { $0.pullRequest?.number == number } }
        if let task = chosen ?? model.board.tasks(in: .ready).first ?? model.board.tasks.first(where: { $0.pullRequest != nil }) ?? model.board.tasks.first {
            model.select(task)
            model.inspectorOpen = true
            await shoot("board-inspector", window)
        }
        model.inspectorOpen = false
        model.selectedTaskID = nil

        model.screen = .overview
        await shoot("overview", window)
        model.screen = .settings
        await shoot("settings", window)

        // Menu bar panel, hosted in a lookalike panel window.
        let panel = makePanelWindow(model: model)
        panel.setFrameTopLeftPoint(NSPoint(x: window.frame.maxX - panel.frame.width - 40, y: window.frame.maxY - 40))
        panel.orderFront(nil)
        await shoot("panel", panel)
        panel.orderOut(nil)

        // Merge confirmation (demo data only; real runs never prepare a write).
        // The sheet's view is hosted in its own window so it can be captured alone.
        if model.mode.demo, let ready = model.board.tasks(in: .ready).first {
            model.request(.merge(.squash), for: ready)
            for _ in 0..<20 where model.writes.pending == nil {
                try? await Task.sleep(for: .milliseconds(150))
            }
            for sheet in window.sheets { window.endSheet(sheet) }
            if let pending = model.writes.pending {
                let host = NSHostingView(rootView: ConfirmWriteSheet(pending: pending)
                    .environment(model)
                    .tint(Theme.accent)
                    .background(VisualEffectBackground(material: .sheet, state: .active)))
                let sheetWindow = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                sheetWindow.isReleasedWhenClosed = false
                sheetWindow.level = .floating
                sheetWindow.contentView = host
                sheetWindow.setFrameTopLeftPoint(NSPoint(x: window.frame.midX - host.fittingSize.width / 2, y: window.frame.maxY - 60))
                sheetWindow.orderFront(nil)
                await shoot("merge-sheet", sheetWindow)
                sheetWindow.orderOut(nil)
            }
            model.writes.cancel()
        }

        try? await Task.sleep(for: .milliseconds(300))
        NSApp.terminate(nil)
    }

    /// Asks `Scripts/snapshots.sh` to capture one window: writes `<name>.request`
    /// with the window id and waits for `<name>.png`. Screen capture runs in the
    /// script's process (which holds the permission), never in the app. Without a
    /// script answering, the view hierarchy is rendered in-process instead
    /// (behind-window blur can't be captured that way).
    private static func capture(_ window: NSWindow, to url: URL) async {
        let request = url.deletingPathExtension().appendingPathExtension("request")
        try? FileManager.default.removeItem(at: url)
        // "<window id> <x> <y> <width> <height>", y measured from the top of the main display.
        let top = NSScreen.screens.first?.frame.maxY ?? window.frame.maxY
        let f = window.frame
        let line = "\(window.windowNumber) \(Int(f.minX)) \(Int(top - f.maxY)) \(Int(f.width)) \(Int(f.height))"
        try? line.write(to: request, atomically: true, encoding: .utf8)
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(150))
            if !FileManager.default.fileExists(atPath: request.path), FileManager.default.fileExists(atPath: url.path) {
                print("snapshot: \(url.lastPathComponent)")
                return
            }
        }
        try? FileManager.default.removeItem(at: request)
        renderInProcess(window, to: url)
        print("snapshot: rendered in-process \(url.lastPathComponent)")
    }

    /// Draws the window's views over its opaque background colour. Translucent
    /// materials come out as that flat colour, since blur can't be rendered here.
    private static func renderInProcess(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let size = rep.size
        let image = NSImage(size: size, flipped: false) { rect in
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
            }
            rep.draw(in: rect)
            return true
        }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let output = NSBitmapImageRep(cgImage: cg)
        output.size = size
        try? output.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func makeBackdrop() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1600, height: 1040), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.contentView = NSHostingView(rootView: Backdrop())
        return window
    }

    private static func makePanelWindow(model: AppModel) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 368, height: 640), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        let root = MenuBarPanel()
            .environment(model)
            .tint(Theme.accent)
            .background(VisualEffectBackground(material: .popover, state: .active))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.strongHairline, lineWidth: 0.5))
        let host = NSHostingView(rootView: root)
        host.frame.size = host.fittingSize
        panel.setContentSize(host.fittingSize)
        panel.contentView = host
        return panel
    }
}

/// Synthetic wallpaper: soft warm and cool blobs, like the reference's backdrop.
private struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
            colors: dark ? [
                .init(red: 0.55, green: 0.30, blue: 0.16), .init(red: 0.32, green: 0.24, blue: 0.16), .init(red: 0.22, green: 0.26, blue: 0.14),
                .init(red: 0.30, green: 0.20, blue: 0.14), .init(red: 0.14, green: 0.13, blue: 0.12), .init(red: 0.17, green: 0.20, blue: 0.13),
                .init(red: 0.20, green: 0.15, blue: 0.12), .init(red: 0.12, green: 0.18, blue: 0.28), .init(red: 0.14, green: 0.14, blue: 0.16),
            ] : [
                .init(red: 0.98, green: 0.80, blue: 0.64), .init(red: 0.93, green: 0.86, blue: 0.76), .init(red: 0.82, green: 0.88, blue: 0.74),
                .init(red: 0.95, green: 0.84, blue: 0.75), .init(red: 0.93, green: 0.91, blue: 0.88), .init(red: 0.84, green: 0.89, blue: 0.80),
                .init(red: 0.92, green: 0.86, blue: 0.80), .init(red: 0.76, green: 0.84, blue: 0.95), .init(red: 0.88, green: 0.88, blue: 0.91),
            ]
        )
        .ignoresSafeArea()
    }
}
