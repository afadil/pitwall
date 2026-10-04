import PitwallCore
import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// App state and the refresh loop. Views read from here; all disk and process
/// work happens in `RefreshEngine` off the main actor.
@Observable
final class AppModel {
    enum Screen: String, CaseIterable, Identifiable {
        case board, overview, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .board: "Board"
            case .overview: "Overview"
            case .settings: "Settings"
            }
        }
        var symbol: String {
            switch self {
            case .board: "rectangle.split.3x1"
            case .overview: "house"
            case .settings: "gearshape"
            }
        }
    }

    var screen: Screen = .board
    var selectedTaskID: String?
    var inspectorOpen = false
    var filterText = ""
    var toast: Toast?
    /// Board column to flash after jumping from Overview.
    var highlightedColumn: BoardColumn?

    /// Lanes, tags and hidden cards, saved to organization.json.
    var organization: Organization {
        didSet {
            guard organization != oldValue else { return }
            persistOrganization()
            rebuild()
        }
    }
    private(set) var organizationProblem: String?
    var tagFilter = TagFilter()
    /// Card that "New tag…" will tag once named.
    var newTagTarget: BoardTask?
    var isNamingNewTag = false

    var settings: BoardSettings {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
            rebuild()
            if settings.refreshInterval != oldValue.refreshInterval { schedulePolling() }
            if settings.showArchived != oldValue.showArchived || settings.excludedRepos != oldValue.excludedRepos {
                Task { await refreshGitHub(onlyIfNewRepos: true) }
            }
        }
    }

    private(set) var local = LocalSnapshot.empty
    private(set) var github = GitHubSnapshot.empty
    private(set) var board = Board.empty
    private(set) var isRefreshingLocal = false
    private(set) var isRefreshingGitHub = false
    private(set) var hasLoaded = false
    private(set) var now = Date()

    let writes: WriteActionCoordinator
    let mode: LaunchOptions
    /// Set by the commands, which have the `openWindow` action; used when the
    /// window has to be opened from outside a view (snapshot runs).
    @ObservationIgnored var openMainWindow: (() -> Void)?
    private let engine: RefreshEngine
    private let paths: DataPaths
    private var watcher: FileWatcher?
    private var pollTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var pendingLocal: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var fetchedSlugs: Set<String> = []
    private let organizationStore = OrganizationStore(url: OrganizationStore.standardURL)
    private static let settingsKey = "BoardSettings.v1"

    init(mode: LaunchOptions = .current) {
        self.mode = mode
        self.paths = DataPaths.standard()
        let gh: GHRunning = mode.demo ? DemoGH() : GHCLI()
        self.engine = RefreshEngine(paths: paths, git: GitCLI(), gh: gh)
        var settings = mode.demo ? BoardSettings() : Self.loadSettings()
        var migratedHidden = false
        if mode.demo {
            self.organization = DemoData.organization()
        } else {
            organizationStore.adoptLegacyFile(at: OrganizationStore.legacyURL)
            let loaded = organizationStore.load()
            var organization = loaded.organization
            // First launch with organization.json: bring hidden cards over from settings.
            if loaded.isNew, !settings.hiddenTaskIDs.isEmpty {
                for id in settings.hiddenTaskIDs { organization.setHidden(true, for: id) }
                settings.hiddenTaskIDs = []
                migratedHidden = true
            }
            organization.prune()
            self.organization = organization
            self.organizationProblem = loaded.problem
        }
        self.settings = settings
        self.writes = WriteActionCoordinator(runner: gh)
        writes.onSuccess = { [weak self] in Task { await self?.refreshGitHub() } }
        if migratedHidden {
            persistOrganization()
            persistSettings()
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        if mode.demo {
            loadDemo()
        } else {
            Task { await refreshAll() }
            watcher = FileWatcher(
                paths: [paths.claudeSessions, paths.claudeProjects, paths.codexHome],
                filter: FileWatcher.relevantFilter(paths: paths)
            ) { [weak self] in
                Task { @MainActor in
                    self?.log("file change")
                    self?.scheduleLocalRefresh()
                }
            }
            schedulePolling()
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self else { return }
                self.now = Date()
                self.rebuild()
            }
        }
    }

    private func loadDemo() {
        let snapshot = DemoData.snapshot(now: Date())
        local = snapshot.local
        github = snapshot.github
        fetchedSlugs = Set(snapshot.github.pullRequests.keys)
        hasLoaded = true
        rebuild()
    }

    func refreshAll() async {
        await refreshLocal()
        await refreshGitHub()
    }

    func refreshLocal() async {
        guard !mode.demo, !isRefreshingLocal else { return }
        isRefreshingLocal = true
        defer { isRefreshingLocal = false }
        let started = Date()
        local = await engine.readLocal(now: Date())
        log("local refresh: \(local.sessions.count) sessions in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        hasLoaded = true
        rebuild()
        // A new branch in a repo we haven't polled yet: fetch its PRs now.
        let slugs = Set(local.githubSlugs(settings: settings))
        if !slugs.isSubset(of: fetchedSlugs), github.fetchedAt != nil {
            Task { await refreshGitHub(onlyIfNewRepos: true) }
        }
    }

    func refreshGitHub(onlyIfNewRepos: Bool = false) async {
        guard !mode.demo, !isRefreshingGitHub else { return }
        let slugs = local.githubSlugs(settings: settings)
        if onlyIfNewRepos, Set(slugs).isSubset(of: fetchedSlugs) { return }
        isRefreshingGitHub = true
        defer { isRefreshingGitHub = false }
        let started = Date()
        github = await engine.fetchGitHub(slugs: slugs, now: Date())
        log("github refresh: \(slugs.count) repos, \(github.errors.count) errors in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        fetchedSlugs = Set(slugs)
        rebuild()
    }

    /// File events arrive in bursts while an agent writes; coalesce them.
    private func scheduleLocalRefresh() {
        pendingLocal?.cancel()
        pendingLocal = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            await self?.refreshLocal()
        }
    }

    private func schedulePolling() {
        pollTask?.cancel()
        let interval = max(15, settings.refreshInterval)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                // Re-read local files too, in case a file event was missed.
                await self.refreshLocal()
                await self.refreshGitHub()
            }
        }
    }

    func rebuild() {
        now = Date()
        let rebuilt = BoardBuilder.build(
            sessions: local.sessions, repos: local.repos, pullRequests: github.pullRequests,
            settings: settings, organization: organization, now: now
        )
        // Only publish real changes, so views and the menu bar don't redraw for nothing.
        if rebuilt != board { board = rebuilt }
        // Remember which organized cards are still around (at most once a day each).
        var seen = organization
        if seen.markSeen(rebuilt.tasks.map(\.id), now: now) { organization = seen }
        if let selectedTaskID, board.task(id: selectedTaskID) == nil {
            self.selectedTaskID = nil
        }
    }

    // MARK: - Derived

    var statuses: [SourceStatus] {
        local.statuses + [github.status(repoCount: local.githubSlugs(settings: settings).count)]
    }

    /// Sources that can't be read, for the board banner.
    var problems: [SourceStatus] {
        guard hasLoaded else { return [] }
        return statuses.filter { status in
            switch status.health {
            case .error: true
            case .missing: status.kind == .github
            case .ok, .warning: false
            }
        }
    }

    var visibleBoard: Board {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty || tagFilter.isActive else { return board }
        var filtered = board
        filtered.tasks = board.tasks.filter { task in
            guard tagFilter.matches(task) else { return false }
            guard !query.isEmpty else { return true }
            return task.title.localizedCaseInsensitiveContains(query)
                || task.tags.contains { $0.name.localizedCaseInsensitiveContains(query) }
                || task.labels.contains { $0.name.localizedCaseInsensitiveContains(query) }
                || task.locationLine.localizedCaseInsensitiveContains(query)
                || task.pullRequest.map { "#\($0.number)".contains(query) || $0.title.localizedCaseInsensitiveContains(query) } ?? false
                || task.sessions.contains { $0.title.localizedCaseInsensitiveContains(query) }
        }
        return filtered
    }

    var selectedTask: BoardTask? { board.task(id: selectedTaskID) }

    /// Board rows for the current grouping, after filters.
    var rows: [BoardRow] {
        BoardLayout.rows(visibleBoard.tasks, grouping: settings.grouping, tags: organization.tags)
    }

    /// "Waiting on you" tasks, newest first: what the menu bar counts.
    var needsYou: [BoardTask] { Self.fastFirst(board.tasks(in: .waiting)) }

    /// Fast-lane cards first, keeping the newest-first order otherwise.
    static func fastFirst(_ tasks: [BoardTask]) -> [BoardTask] {
        tasks.filter { $0.lane == .fast } + tasks.filter { $0.lane != .fast }
    }

    func timelineBlocks(calendar: Calendar = .current) -> [TimelineBlock] {
        guard let day = calendar.dateInterval(of: .day, for: now) else { return [] }
        return Timeline.blocks(for: board.tasks, in: day)
    }

    var lastUpdated: Date? {
        [local.readAt == .distantPast ? nil : local.readAt, github.fetchedAt].compactMap { $0 }.max()
    }

    var isRefreshing: Bool { isRefreshingLocal || isRefreshingGitHub }

    var organizationFilePath: String { organizationStore.url.path }

    func show(_ kind: Toast.Kind, _ message: String) {
        toast = Toast(kind: kind, message: message)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func log(_ message: String) {
        guard mode.verbose else { return }
        print("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
    }

    // MARK: - Settings persistence

    /// Defaults domain of builds from before the rename (Agent Board).
    private static let legacyDefaultsDomain = "local.agentboard.AgentBoard"

    private static func loadSettings() -> BoardSettings {
        adoptLegacyDefaults()
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(BoardSettings.self, from: data) else { return BoardSettings() }
        return settings
    }

    /// Copies preferences saved under the old bundle id, once.
    private static func adoptLegacyDefaults() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: settingsKey) == nil,
              let legacy = UserDefaults(suiteName: legacyDefaultsDomain) else { return }
        for key in [settingsKey, "doneCollapsed", "collapsedRows"] {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    private func persistOrganization() {
        guard !mode.demo else { return }
        do {
            try organizationStore.save(organization)
        } catch {
            organizationProblem = "Can't save organization.json: \(error.localizedDescription)"
        }
    }

    private func persistSettings() {
        guard !mode.demo, let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }
}
