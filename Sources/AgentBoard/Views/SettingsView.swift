import AgentBoardCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader("Settings")
                    .frame(maxWidth: 760)
                VStack(alignment: .leading, spacing: 28) {
                    generalSection
                    repositoriesSection
                    sourcesSection
                    privacyNote
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }

    // MARK: General

    private var generalSection: some View {
        @Bindable var model = model
        return SettingsGroup(title: "General") {
            SettingsRow("Refresh GitHub every", detail: "Local files are watched and refresh on their own.") {
                Picker("Refresh GitHub every", selection: $model.settings.refreshInterval) {
                    ForEach(BoardSettings.refreshChoices, id: \.self) { seconds in
                        Text(seconds < 60 ? "\(Int(seconds)) seconds" : seconds == 60 ? "1 minute" : "\(Int(seconds / 60)) minutes")
                            .tag(seconds)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsDivider()
            SettingsRow("Show archived sessions", detail: "Sessions you archived in Claude or Codex.") {
                Toggle("Show archived sessions", isOn: $model.settings.showArchived).labelsHidden().toggleStyle(.switch)
            }
            SettingsDivider()
            SettingsRow("Show hidden cards", detail: "\(model.settings.hiddenTaskIDs.count) hidden") {
                Toggle("Show hidden cards", isOn: $model.settings.showHidden).labelsHidden().toggleStyle(.switch)
            }
            SettingsDivider()
            SettingsRow("Open folders in", detail: nil) {
                Picker("Open folders in", selection: $model.settings.folderOpener) {
                    Text("Finder").tag(FolderOpener.finder)
                    Text("Terminal").tag(FolderOpener.terminal)
                    Text(AppModel.editorName).tag(FolderOpener.editor)
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsDivider()
            SettingsRow("Show in menu bar", detail: "Counts what's waiting on you.") {
                Toggle("Show in menu bar", isOn: $model.settings.showMenuBarExtra).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: Repositories

    private var repositoriesSection: some View {
        SettingsGroup(title: "Repositories", footer: "Turn a repository off to leave it off the board and stop polling it.") {
            if model.board.repos.isEmpty {
                Text(model.hasLoaded ? "No repositories found in your sessions." : "Reading sessions…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
            }
            ForEach(Array(model.board.repos.enumerated()), id: \.element) { index, repo in
                if index > 0 { SettingsDivider() }
                RepoToggleRow(repo: repo)
            }
        }
    }

    // MARK: Data sources

    private var sourcesSection: some View {
        SettingsGroup(title: "Data sources", footer: "Read-only. Agent Board never writes to these folders and only reads the end of each transcript.") {
            ForEach(Array(model.statuses.enumerated()), id: \.element.id) { index, status in
                if index > 0 { SettingsDivider() }
                SourceRow(status: status)
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            Text("Agent Board talks to the network only through the gh CLI, using your existing login. No tokens are read or stored, and nothing is sent anywhere else.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

private struct RepoToggleRow: View {
    @Environment(AppModel.self) private var model
    let repo: RepoID

    var body: some View {
        let included = !model.settings.excludedRepos.contains(repo.key)
        let count = model.board.tasks.filter { $0.repo == repo }.count
        SettingsRow(repo.displayName, detail: detail(count: count), mono: true) {
            Toggle(repo.displayName, isOn: Binding(
                get: { included },
                set: { on in
                    if on { model.settings.excludedRepos.remove(repo.key) } else { model.settings.excludedRepos.insert(repo.key) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    private func detail(count: Int) -> String {
        var parts: [String] = []
        if repo.githubSlug == nil { parts.append(repo.host == nil ? "Local, no remote" : "Not on GitHub") }
        if !model.settings.excludedRepos.contains(repo.key) { parts.append("\(count) task\(count == 1 ? "" : "s")") }
        else { parts.append("Excluded") }
        return parts.joined(separator: " · ")
    }
}

private struct SourceRow: View {
    let status: SourceStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HealthIcon(health: status.health)
                .font(.body)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.title).font(.callout.weight(.medium))
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(status.health == .ok ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(Format.path(status.path))
                    .font(Theme.monoSmall)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if status.kind != .github, FileManager.default.fileExists(atPath: status.path) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: status.path)])
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

/// Grouped section in the style of System Settings.
struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .surface(radius: 12)
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    var mono = false
    @ViewBuilder var control: Control

    init(_ title: String, detail: String?, mono: Bool = false, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.mono = mono
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(mono ? Theme.mono.weight(.medium) : .callout)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 14)
    }
}
