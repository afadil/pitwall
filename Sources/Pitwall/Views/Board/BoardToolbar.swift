import PitwallCore
import SwiftUI

struct BoardToolbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            GroupingMenu()
            TagFilterMenu()
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Filter", text: $model.filterText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                    .accessibilityLabel("Filter tasks")
                if !model.filterText.isEmpty {
                    Button {
                        model.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filter")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))

            SoftIconButton(
                symbol: model.settings.showHidden ? "eye" : "eye.slash",
                label: model.settings.showHidden ? "Hide hidden cards" : "Show hidden cards", size: 30
            ) {
                model.settings.showHidden.toggle()
            }
            SoftIconButton(symbol: "arrow.clockwise", label: "Refresh  ⌘R", size: 30) {
                Task { await model.refreshAll() }
            }
            .disabled(model.isRefreshing)
            SoftIconButton(symbol: "sidebar.right", label: model.inspectorOpen ? "Hide details" : "Show details", size: 30) {
                if model.selectedTaskID == nil { model.select(model.visibleBoard.tasks.first) }
                model.inspectorOpen.toggle()
            }
        }
    }
}

struct GroupingMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Group by", selection: $model.settings.grouping) {
                ForEach(Grouping.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            ToolbarMenuLabel(symbol: "rectangle.grid.1x2", text: "By \(model.settings.grouping.title.lowercased())", active: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Group rows by lane, tag or repository")
        .accessibilityLabel("Group by \(model.settings.grouping.title)")
    }
}

struct TagFilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let labels = BoardLayout.labels(in: model.board.tasks)
        Menu {
            if model.organization.tags.isEmpty && labels.isEmpty {
                Text("No tags yet. Right-click a card to add one.")
            }
            if !model.organization.tags.isEmpty {
                Section("Your tags") {
                    ForEach(model.organization.tags) { tag in
                        Toggle(
                            isOn: Binding(
                                get: { model.tagFilter.tagIDs.contains(tag.id) },
                                set: { _ in model.tagFilter.toggle(tag: tag.id) })
                        ) {
                            Label {
                                Text(tag.name)
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(tag.color.color)
                            }
                        }
                    }
                }
            }
            if !labels.isEmpty {
                Section("GitHub labels") {
                    ForEach(labels, id: \.name) { label in
                        Toggle(
                            label.name,
                            isOn: Binding(
                                get: { model.tagFilter.labels.contains(label.name.lowercased()) },
                                set: { _ in model.tagFilter.toggle(label: label.name) }))
                    }
                }
            }
            Divider()
            Picker("Match", selection: $model.tagFilter.mode) {
                Text("Any selected tag").tag(TagFilter.Mode.any)
                Text("All selected tags").tag(TagFilter.Mode.all)
            }
            .pickerStyle(.inline)
            if model.tagFilter.isActive {
                Button("Clear tag filter") { model.tagFilter = TagFilter(mode: model.tagFilter.mode) }
            }
        } label: {
            ToolbarMenuLabel(
                symbol: "tag", text: model.tagFilter.isActive ? "\(model.tagFilter.count)" : "Tags",
                active: model.tagFilter.isActive)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter by tags and GitHub labels")
        .accessibilityLabel(model.tagFilter.isActive ? "Tag filter, \(model.tagFilter.count) selected" : "Filter by tag")
    }
}
