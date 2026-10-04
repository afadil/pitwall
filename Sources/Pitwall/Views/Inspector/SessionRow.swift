import PitwallCore
import SwiftUI

struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let session: AgentSession
    let linked: Bool
    /// Per-session "Open in …" when the card has several sessions (the header covers one).
    let showOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AppBadge(app: session.app)
                Text(state)
                    .font(.caption)
                    .foregroundStyle(session.turn == .running ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.secondary))
                Spacer()
                Text(Format.ago(session.lastActivity, now: model.now))
                    .font(Theme.monoSmall)
                    .foregroundStyle(.tertiary)
            }
            Text(session.title)
                .font(.callout)
                .lineLimit(2)
            if linked {
                Text("Opened this pull request, now on \(session.branch ?? "another branch")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showOpen, session.appURL != nil {
                Button {
                    model.openInApp(session)
                } label: {
                    Label("Open in \(session.app.displayName)", systemImage: "arrow.up.forward.app")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
            if let command = session.resumeCommand {
                Button {
                    model.copyResumeCommand(session)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal").font(.caption2)
                        Text(command.components(separatedBy: " && ").last ?? command)
                            .font(Theme.monoSmall)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: "doc.on.doc").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy: \(command)")
                .accessibilityLabel("Copy \(session.app.displayName) resume command")
            }
        }
        .padding(12)
    }

    private var state: String {
        switch session.turn {
        case .running: "Turn running"
        case .ended: session.isArchived ? "Archived" : "Turn ended"
        case .unknown: "State unknown"
        }
    }
}
