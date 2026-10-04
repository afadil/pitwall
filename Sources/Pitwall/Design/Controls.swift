import AppKit
import PitwallCore
import SwiftUI

/// Soft, rounded icon button (the "tactile" control from the references).
struct SoftIconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 28
    var prominent = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                .background(
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                        .fill(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(hovered ? 0.11 : 0.06)))
                )
                .contentShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Capsule button with icon and text, like the panel's "Stop" control in the reference.
struct PillButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.caption.weight(.bold))
                Text(title).font(.callout.weight(.medium))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background(
                Capsule().fill(
                    prominent
                        ? AnyShapeStyle(Theme.accent.opacity(hovered ? 0.9 : 1))
                        : AnyShapeStyle(Color.primary.opacity(hovered ? 0.13 : 0.08)))
            )
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: prominent ? 0 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Soft segmented control in the style of the references: a recessed track with
/// a raised pill on the selected segment. Exposed to VoiceOver as selectable buttons.
struct SoftSegmentedControl<Value: Hashable & Identifiable>: View {
    let label: String
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(light: .white, dark: NSColor(white: 1, alpha: 0.14)))
                                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Soft capsule label for toolbar menus, matching the other toolbar controls.
struct ToolbarMenuLabel: View {
    let symbol: String
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption.weight(.semibold))
            Text(text).font(.callout)
        }
        .foregroundStyle(active ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(active ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.06))
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}
