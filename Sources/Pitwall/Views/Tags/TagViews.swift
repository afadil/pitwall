import PitwallCore
import SwiftUI

/// Your tag: coloured dot and name.
struct TagChip: View {
    let tag: CardTag
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tag.color.color).frame(width: 6, height: 6)
            Text(tag.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove tag \(tag.name)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tag.color.color.opacity(0.10)))
        .overlay(Capsule().strokeBorder(tag.color.color.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: onRemove == nil ? .ignore : .contain)
        .accessibilityLabel("Tag \(tag.name)")
    }
}

/// A GitHub label: ring instead of a dot, so it reads as coming from GitHub.
struct LabelChip: View {
    let label: PRLabel

    var body: some View {
        HStack(spacing: 4) {
            Circle().strokeBorder(Self.color(label.color), lineWidth: 1.5).frame(width: 7, height: 7)
            Text(label.name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GitHub label \(label.name)")
    }

    static func color(_ hex: String?) -> Color {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return .secondary }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// Tags and labels on a card: up to three chips, then "+N".
struct CardTagsRow: View {
    let task: BoardTask

    var body: some View {
        let tags = task.tags
        let labels = task.labels
        let shown = 3
        HStack(spacing: 4) {
            ForEach(tags.prefix(shown)) { TagChip(tag: $0) }
            ForEach(labels.prefix(max(0, shown - tags.count)), id: \.name) { LabelChip(label: $0) }
            let extra = tags.count + labels.count - shown
            if extra > 0 {
                Text(verbatim: "+\(extra)")
                    .font(Theme.monoSmall)
                    .foregroundStyle(.tertiary)
                    .help((tags.dropFirst(shown).map(\.name) + labels.map(\.name)).joined(separator: ", "))
            }
        }
        .lineLimit(1)
    }
}

/// Names a new tag, then adds it to the card it was started from.
struct NewTagAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    func body(content: Content) -> some View {
        @Bindable var model = model
        content.alert("New tag", isPresented: $model.isNamingNewTag) {
            TextField("Name", text: $name)
            Button("Add") {
                model.createTag(named: name, for: model.newTagTarget)
                name = ""
                model.newTagTarget = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                name = ""
                model.newTagTarget = nil
            }
        } message: {
            if let task = model.newTagTarget {
                Text("Adds the tag to “\(task.title)”.")
            }
        }
    }
}
