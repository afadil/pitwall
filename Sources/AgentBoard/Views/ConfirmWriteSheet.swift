import AgentBoardCore
import SwiftUI

/// Names the pull request and the exact `gh` command before any write to GitHub.
struct ConfirmWriteSheet: View {
    @Environment(AppModel.self) private var model
    let pending: PendingWrite

    private var pr: PullRequest { pending.pullRequest }

    private var isMerge: Bool {
        if case .merge = pending.action { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isMerge ? "arrow.trianglehead.merge" : "eye")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isMerge ? "Merge pull request #\(pr.number)?" : "Mark pull request #\(pr.number) ready for review?")
                        .font(.headline)
                    Text(pr.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                row("Repository", pr.repo)
                row("Branch", "\(pr.headRefName) → \(pr.baseRefName ?? "default")")
                row("Checks", pr.checks.state.label)
                row("Review", pr.reviewDecision.label ?? "No review required")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(radius: 10)

            if isMerge, pending.allowedMethods.count > 1 {
                Picker("Merge method", selection: Binding(
                    get: { if case let .merge(method) = pending.action { method } else { .squash } },
                    set: { model.writes.choose($0) }
                )) {
                    ForEach(pending.allowedMethods) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("This runs on GitHub with your gh login and can't be undone from Agent Board:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("gh " + pending.arguments.joined(separator: " "))
                    .font(Theme.monoSmall)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
            }

            HStack {
                if model.writes.isPerforming {
                    ProgressView().controlSize(.small)
                    Text(isMerge ? "Merging…" : "Updating…").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.writes.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(isMerge ? "Merge" : "Mark ready") { model.confirmWrite() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(model.writes.isPerforming)
            }
        }
        .padding(24)
        .frame(width: 460)
        .accessibilityElement(children: .contain)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(Theme.mono)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }
}
