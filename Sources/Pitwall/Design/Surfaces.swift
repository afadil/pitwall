import AppKit
import PitwallCore
import SwiftUI

/// Behind-window vibrancy. Falls back to an opaque fill automatically when
/// Reduce Transparency is on (NSVisualEffectView handles that itself).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = state
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = state
    }
}

/// Monospaced section heading, sentence case.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.sectionLabel)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
    }
}

/// Rounded surface with a hairline, used by cards and panels.
struct Surface: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var hovered = false
    var selected = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cardFill(hovered: hovered, reduceTransparency: reduceTransparency))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 1.5 : 0.5)
            )
    }
}

extension View {
    func surface(radius: CGFloat = Theme.cardRadius, hovered: Bool = false, selected: Bool = false) -> some View {
        modifier(Surface(radius: radius, hovered: hovered, selected: selected))
    }
}
