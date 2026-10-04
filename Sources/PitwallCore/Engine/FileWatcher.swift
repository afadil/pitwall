import CoreServices
import Foundation

/// Watches folders with FSEvents and reports changes to the files that matter.
///
/// Watching is passive: FSEvents only observes, it never opens or locks files.
public final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "pitwall.filewatcher")
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
    /// FSEvents reports resolved paths (`/private/var/…`), so both the given and
    /// the symlink-resolved form of each folder are accepted.
    public static func relevantFilter(paths: DataPaths) -> @Sendable (String) -> Bool {
        // `URL.resolvingSymlinksInPath` strips `/private`, so use realpath(3).
        func forms(_ url: URL) -> [String] {
            var result = [url.path]
            if let resolved = realpath(url.path, nil) {
                result.append(String(cString: resolved))
                free(resolved)
            }
            return Array(Set(result))
        }
        let sessions = forms(paths.claudeSessions)
        let projects = forms(paths.claudeProjects)
        let codexHome = forms(paths.codexHome)
        let codexSessions = forms(paths.codexSessions)
        return { path in
            func under(_ prefixes: [String]) -> Bool { prefixes.contains { path.hasPrefix($0 + "/") } }
            if under(sessions) { return path.hasSuffix(".json") }
            if under(projects) { return path.hasSuffix(".jsonl") }
            if under(codexSessions) { return path.hasSuffix(".jsonl") }
            if under(codexHome) {
                let name = (path as NSString).lastPathComponent
                return name.hasPrefix("state_") && name.contains(".sqlite")
            }
            return false
        }
    }
}
