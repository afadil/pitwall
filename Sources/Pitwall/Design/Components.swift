import PitwallCore
import AppKit
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

/// Small capsule naming the app a session came from, with its timeline colour.
struct AppBadge: View {
    let app: AgentApp
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(app.tint)
                .frame(width: 6, height: 6)
            if !compact {
                Text(app.displayName)
                    .font(Theme.monoSmall.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.displayName)
    }
}

/// An orange dot that breathes while an agent is working. Static with Reduce Motion.
struct PulseDot: View {
    var color: Color = Theme.accent
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: size, height: size)
                    .scaleEffect(pulsing ? 2.3 : 1)
                    .opacity(pulsing ? 0 : 0.9)
            }
            Circle().fill(color).frame(width: size, height: size)
        }
        .frame(width: size * 2.3, height: size * 2.3)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulsing = true }
        }
        .accessibilityHidden(true)
    }
}

/// Inline status: tinted SF Symbol plus label.
struct StatusLabel: View {
    let symbol: String
    let text: String
    let color: Color
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(font.weight(.semibold))
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tinted pill used for the "In review" reason.
struct ReasonPill: View {
    let reason: ReviewReason
    /// Overrides the label, e.g. "Stacked on #41".
    var text: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: reason.symbol)
                .font(.caption2.weight(.bold))
            Text(text ?? reason.label)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(reason.color == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(reason.color))
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(reason.color.opacity(reason.color == .secondary ? 0.10 : 0.14)))
        .accessibilityElement(children: .combine)
    }
}

/// `#412` chip with PR state colour.
struct PRChip: View {
    let pr: PullRequest

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: pr.stateSymbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(pr.stateColor)
            Text(verbatim: "#\(pr.number)")
                .font(Theme.monoMedium)
                .foregroundStyle(.primary.opacity(0.85))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pull request \(pr.number), \(pr.stateLabel)")
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
                Capsule().fill(prominent ? AnyShapeStyle(Theme.accent.opacity(hovered ? 0.9 : 1)) : AnyShapeStyle(Color.primary.opacity(hovered ? 0.13 : 0.08)))
            )
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: prominent ? 0 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Transient confirmation shown at the bottom of a screen.
struct Toast: Identifiable, Equatable {
    enum Kind { case success, failure, info }
    let id = UUID()
    var kind: Kind
    var message: String
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.callout.weight(.semibold))
            Text(toast.message)
                .font(.callout)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var symbol: String {
        switch toast.kind {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var color: Color {
        switch toast.kind {
        case .success: Theme.success
        case .failure: Theme.failure
        case .info: Theme.accent
        }
    }
}

/// Health glyph for a data source.
struct HealthIcon: View {
    let health: SourceStatus.Health

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch health {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .missing: "questionmark.circle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch health {
        case .ok: Theme.success
        case .warning: Theme.pending
        case .missing: .secondary
        case .error: Theme.failure
        }
    }

    private var label: String {
        switch health {
        case .ok: "Readable"
        case .warning: "Partly readable"
        case .missing: "Not found"
        case .error: "Can't read"
        }
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
