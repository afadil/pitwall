import PitwallCore
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
                    tagsSection
                    repositoriesSection
                    sourcesSection
                    organizationSection
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
            SettingsRow("Show hidden cards", detail: "\(model.organization.cards.values.filter(\.hidden).count) hidden") {
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
            SettingsRow("Fast lane limit", detail: "The lane warns when it holds more cards than this.") {
                Stepper(value: $model.settings.fastLaneLimit, in: 1...10) {
                    Text(verbatim: "\(model.settings.fastLaneLimit)").font(Theme.monoMedium).frame(minWidth: 18)
                }
                .fixedSize()
                .accessibilityLabel("Fast lane limit")
                .accessibilityValue("\(model.settings.fastLaneLimit)")
            }
            SettingsDivider()
            SettingsRow("Show in menu bar", detail: "Counts what's waiting on you.") {
                Toggle("Show in menu bar", isOn: $model.settings.showMenuBarExtra).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: Repositories

    // MARK: Tags

    private var tagsSection: some View {
        SettingsGroup(
            title: "Tags",
            footer:
                "Tags are yours: add as many as you like to any card, then filter or group the board by them. GitHub labels show up on their own."
        ) {
            ForEach(Array(model.organization.tags.enumerated()), id: \.element.id) { index, tag in
                if index > 0 { SettingsDivider() }
                TagSettingsRow(tag: tag)
            }
            if !model.organization.tags.isEmpty { SettingsDivider() }
            NewTagRow()
        }
    }

    private var organizationSection: some View {
        SettingsGroup(title: "Your organization", footer: "Lanes, tags and hidden cards. Pitwall writes only this file, in its own folder.")
        {
            HStack(alignment: .top, spacing: 12) {
                HealthIcon(health: model.organizationProblem == nil ? .ok : .warning)
                    .font(.body)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("organization.json").font(.callout.weight(.medium))
                    Text(model.organizationProblem ?? organizationSummary)
                        .font(.caption)
                        .foregroundStyle(model.organizationProblem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Format.path(model.organizationFilePath))
                        .font(Theme.monoSmall)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                if FileManager.default.fileExists(atPath: model.organizationFilePath) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: model.organizationFilePath)])
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var organizationSummary: String {
        let org = model.organization
        let lanes = org.cards.values.filter { $0.lane != nil }.count
        let tagged = org.cards.values.filter { !$0.tagIDs.isEmpty }.count
        let hidden = org.cards.values.filter(\.hidden).count
        return "\(org.tags.count) tag\(org.tags.count == 1 ? "" : "s") · \(tagged) tagged · \(lanes) in a lane · \(hidden) hidden"
    }

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
        SettingsGroup(
            title: "Data sources", footer: "Read-only. Pitwall never writes to these folders and only reads the end of each transcript."
        ) {
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
            Text(
                "Pitwall talks to the network only through the gh CLI, using your existing login. No tokens are read or stored, and nothing is sent anywhere else."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}
