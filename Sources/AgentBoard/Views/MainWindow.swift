import AgentBoardCore
import SwiftUI

/// Translucent window with an icon rail and an inset content panel,
/// modelled on the overview reference.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            Rail()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                        .fill(Theme.panelFill(reduceTransparency: reduceTransparency))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
                .padding([.top, .bottom, .trailing], 8)
        }
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 28)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.animation(reduceMotion), value: model.toast)
        .sheet(item: Binding(get: { model.writes.pending }, set: { if $0 == nil { model.writes.cancel() } })) { pending in
            ConfirmWriteSheet(pending: pending)
                .environment(model)
        }
        .modifier(NewTagAlert())
        .frame(minWidth: 980, minHeight: 600)
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .board: BoardView()
        case .overview: OverviewView()
        case .settings: SettingsView()
        }
    }
}

/// Narrow navigation rail. Traffic lights sit above the first item.
struct Rail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            Color.clear.frame(height: 44) // room for the traffic lights
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

/// The app's mark: an orange tile with three columns, matching the icon.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.82)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                HStack(alignment: .top, spacing: size * 0.08) {
                    ForEach([3, 2, 1], id: \.self) { count in
                        VStack(spacing: size * 0.08) {
                            ForEach(0..<count, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                                    .fill(.white.opacity(0.95))
                                    .frame(width: size * 0.18, height: size * 0.13)
                            }
                        }
                    }
                }
                .frame(height: size * 0.55, alignment: .top)
            }
            .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.15, y: size * 0.05)
    }
}

/// Large title row shared by every screen.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 16)
    }
}

/// Slim banner for sources that can't be read.
struct ProblemBanner: View {
    @Environment(AppModel.self) private var model
    let problems: [SourceStatus]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.pending)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(problems) { problem in
                    Text("\(problem.title): \(problem.detail)")
                        .font(.callout)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Details") { model.screen = .settings }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.pending.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.pending.opacity(0.3), lineWidth: 0.5))
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }
}
