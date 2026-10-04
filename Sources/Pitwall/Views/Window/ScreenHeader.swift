import PitwallCore
import SwiftUI

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
