import CoreServices
import Foundation

/// Watches folders with FSEvents and reports changes to the files that matter.
///
/// Watching is passive: FSEvents only observes, it never opens or locks files.
public final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "agentboard.filewatcher")
    private let filter: @Sendable (String) -> Bool
    private let onChange: @Sendable () -> Void

    /// - Parameters:
    ///   - paths: folders to watch (missing ones are skipped).
    ///   - filter: returns true for changed paths that should trigger a refresh.
    public init(paths: [URL], latency: TimeInterval = 1.0, filter: @escaping @Sendable (String) -> Bool, onChange: @escaping @Sendable () -> Void) {
        self.filter = filter
        self.onChange = onChange
        let existing = paths.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let array = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            if array.prefix(count).contains(where: watcher.filter) {
                watcher.onChange()
            }
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(nil, callback, &context, existing as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Paths under the agent data folders that should trigger a re-read.
    public static func relevantFilter(paths: DataPaths) -> @Sendable (String) -> Bool {
        let sessions = paths.claudeSessions.path
        let projects = paths.claudeProjects.path
        let codexHome = paths.codexHome.path
        let codexSessions = paths.codexSessions.path
        return { path in
            if path.hasPrefix(sessions) { return path.hasSuffix(".json") }
            if path.hasPrefix(projects) { return path.hasSuffix(".jsonl") }
            if path.hasPrefix(codexSessions) { return path.hasSuffix(".jsonl") }
            if path.hasPrefix(codexHome) {
                let name = (path as NSString).lastPathComponent
                return name.hasPrefix("state_") && name.contains(".sqlite")
            }
            return false
        }
    }
}
