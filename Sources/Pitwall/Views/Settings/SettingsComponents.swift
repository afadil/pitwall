import PitwallCore
import SwiftUI

/// Grouped section in the style of System Settings.
struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .surface(radius: 12)
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    var mono = false
    @ViewBuilder var control: Control

    init(_ title: String, detail: String?, mono: Bool = false, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.mono = mono
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(mono ? Theme.mono.weight(.medium) : .callout)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 14)
    }
}
