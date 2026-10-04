import PitwallCore
import SwiftUI

/// Narrow navigation rail. Traffic lights sit above the first item.
struct Rail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            Color.clear.frame(height: 44)  // room for the traffic lights
            AppMark(size: 30)
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            RailButton(screen: .board, shortcut: "1")
            RailButton(screen: .overview, shortcut: "2")
            Spacer()
            RailButton(screen: .settings, shortcut: ",")
            GitHubStatusDot()
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .frame(width: 76)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }
}

private struct RailButton: View {
    @Environment(AppModel.self) private var model
    let screen: AppModel.Screen
    let shortcut: String
    @State private var hovered = false

    var body: some View {
        let selected = model.screen == screen
        Button {
            model.screen = screen
        } label: {
            Image(systemName: selected ? screen.symbol + ".fill" : screen.symbol)
                .font(.system(size: 17, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 42, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.primary.opacity(selected ? 0.11 : hovered ? 0.06 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("\(screen.title)  ⌘\(shortcut)")
        .accessibilityLabel(screen.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// gh status at the foot of the rail.
private struct GitHubStatusDot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.statuses.first { $0.kind == .github }
        Button {
            model.screen = .settings
        } label: {
            ZStack {
                Circle().fill(Color.primary.opacity(0.07)).frame(width: 30, height: 30)
                if model.isRefreshing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Circle()
                    .fill(color(status?.health))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .offset(x: 10, y: 10)
            }
        }
        .buttonStyle(.plain)
        .help(status.map { "GitHub: \($0.detail)" } ?? "GitHub")
        .accessibilityLabel(status.map { "GitHub status: \($0.detail)" } ?? "GitHub status")
    }

    private func color(_ health: SourceStatus.Health?) -> Color {
        switch health {
        case .ok?: Theme.success
        case .warning?: Theme.pending
        case .error?, .missing?: Theme.failure
        case nil: .secondary
        }
    }
}
