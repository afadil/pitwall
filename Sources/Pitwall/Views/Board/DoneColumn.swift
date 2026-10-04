import PitwallCore
import SwiftUI

/// Done: a compact list that can fold into a slim strip.
struct DoneColumnView: View {
    @Environment(AppModel.self) private var model
    let tasks: [BoardTask]
    @Binding var collapsed: Bool

    var body: some View {
        if collapsed {
            Button {
                collapsed = false
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: BoardColumn.done.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text("\(tasks.count)")
                        .font(Theme.monoMedium)
                        .foregroundStyle(.secondary)
                    Text("Done")
                        .font(.caption.weight(.semibold))
                        .fixedSize()
                        .rotationEffect(.degrees(90))
                        .frame(width: 20, height: 44)
                    Spacer()
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show done")
            .accessibilityLabel("Done, \(tasks.count) tasks, collapsed. Expand")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ColumnHeader(column: .done, count: tasks.count)
                    Button {
                        collapsed = true
                    } label: {
                        Image(systemName: "chevron.right.2")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Collapse done")
                    .accessibilityLabel("Collapse done")
                }
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        if tasks.isEmpty {
                            EmptyColumn(message: BoardColumn.done.emptyMessage)
                        }
                        ForEach(tasks) { task in
                            DoneRow(task: task)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Done, \(tasks.count) tasks")
        }
    }
}

private struct DoneRow: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask
    @State private var hovered = false

    var body: some View {
        let selected = model.selectedTaskID == task.id
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: task.pullRequest?.stateSymbol ?? "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(task.pullRequest?.stateColor ?? .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(task.pullRequest.map { "#\($0.number) · \(task.repo?.name ?? "")" } ?? task.locationLine)
                    .font(Theme.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Format.ago(task.pullRequest?.finishedAt ?? task.lastActivity, now: model.now))
                .font(Theme.monoSmall)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.14) : Color.primary.opacity(hovered ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .gesture(TapGesture(count: 2).onEnded { model.openInApp(task) })
        .simultaneousGesture(TapGesture().onEnded {
            model.select(task)
            model.inspectorOpen = true
        })
        .contextMenu { TaskActionsMenu(task: task) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TaskCard.accessibilityDescription(task, now: model.now))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.select(task); model.inspectorOpen = true }
        .accessibilityActions { TaskAccessibilityActions(task: task) }
    }
}
