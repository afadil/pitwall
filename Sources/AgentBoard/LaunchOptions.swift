import AppKit
import Foundation

/// Command-line switches, used for demos and screenshot runs.
///
///     --demo                     synthetic data, no disk reads, no GitHub
///     --appearance dark|light    force an appearance
///     --snapshot-dir <path>      render every screen, capture it, then quit
///     --snapshot-prefix <name>   file name prefix for captures
///     --render-icon <path>       write the app icon artwork and quit
///     --verbose                  log refreshes to stdout
///     --snapshot-select <PR>     show this PR's card in the details snapshot
struct LaunchOptions: Sendable {
    var demo = false
    var appearance: String?
    var snapshotDirectory: URL?
    var snapshotPrefix = "agentboard"
    var renderIconDirectory: URL?
    var verbose = false
    var snapshotSelect: Int?

    static let current = LaunchOptions(arguments: CommandLine.arguments)

    init(arguments: [String] = []) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--demo": demo = true
            case "--verbose": verbose = true
            case "--snapshot-select": snapshotSelect = iterator.next().flatMap { Int($0) }
            case "--appearance": appearance = iterator.next()
            case "--snapshot-dir": snapshotDirectory = iterator.next().map { URL(filePath: $0, directoryHint: .isDirectory) }
            case "--snapshot-prefix": snapshotPrefix = iterator.next() ?? snapshotPrefix
            case "--render-icon": renderIconDirectory = iterator.next().map { URL(filePath: $0, directoryHint: .isDirectory) }
            default: break
            }
        }
    }

    var isSnapshotRun: Bool { snapshotDirectory != nil }

    @MainActor
    func applyAppearance() {
        switch appearance {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }
}
