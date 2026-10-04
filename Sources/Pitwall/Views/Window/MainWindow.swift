import PitwallCore
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
