import PitwallCore
import SwiftUI

struct RepoToggleRow: View {
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

struct SourceRow: View {
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

/// Rename, recolour or delete a tag.
struct TagSettingsRow: View {
    @Environment(AppModel.self) private var model
    let tag: CardTag
    @State private var name = ""

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(TagColor.allCases) { color in
                    Button {
                        model.organization.recolorTag(tag.id, to: color)
                    } label: {
                        Label { Text(color.title) } icon: { Image(systemName: "circle.fill").foregroundStyle(color.color) }
                    }
                }
            } label: {
                Circle().fill(tag.color.color).frame(width: 12, height: 12)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Colour")
            .accessibilityLabel("Colour of \(tag.name): \(tag.color.title)")
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { model.organization.renameTag(tag.id, to: name); name = tag.name }
                .accessibilityLabel("Tag name")
            Spacer()
            let count = model.cardsUsing(tag)
            Text("\(count) card\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                model.deleteTag(tag)
            } label: {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Delete tag")
            .accessibilityLabel("Delete tag \(tag.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear { name = tag.name }
        .onChange(of: tag.name) { _, new in name = new }
    }
}

/// Adds a tag without a card.
struct NewTagRow: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle").foregroundStyle(.secondary)
            TextField("New tag", text: $name)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit(add)
                .accessibilityLabel("New tag name")
            Spacer()
            Button("Add", action: add)
                .controlSize(.small)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func add() {
        guard model.createTag(named: name) != nil else { return }
        name = ""
    }
}
