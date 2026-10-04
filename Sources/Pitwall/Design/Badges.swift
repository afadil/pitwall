import PitwallCore
import AppKit
import SwiftUI

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

struct ColumnPill: View {
    let column: BoardColumn

    var body: some View {
        HStack(spacing: 5) {
            if column == .working {
                PulseDot(size: 5).frame(width: 10, height: 10)
            } else {
                Image(systemName: column.symbol).font(.system(size: 9, weight: .bold))
            }
            Text(column.title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(column == .working || column == .waiting ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(column == .working || column == .waiting ? Theme.accent.opacity(0.13) : Color.primary.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}
