import PitwallCore
import SwiftUI

struct ColumnHeader: View {
    let column: BoardColumn
    let count: Int
    var highlighted = false

    var body: some View {
        HStack(spacing: 7) {
            if column == .working, count > 0 {
                PulseDot(size: 6)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: column.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(column == .waiting && count > 0 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    .frame(width: 14, height: 14)
            }
            Text(column.title)
                .font(.subheadline.weight(.semibold))
            Text("\(count)")
                .font(Theme.monoMedium)
                .foregroundStyle(column == .waiting && count > 0 ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.secondary))
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accent.opacity(highlighted ? 0.14 : 0))
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyColumn: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
    }
}

/// Column titles above the lanes, aligned with the lane cells.
struct ColumnHeaderRow: View {
    let columns: [BoardColumn]
    let counts: [BoardColumn: Int]
    let width: CGFloat
    let spacing: CGFloat
    var highlighted: BoardColumn?

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(columns) { column in
                ColumnHeader(column: column, count: counts[column] ?? 0, highlighted: highlighted == column)
                    .frame(width: width)
            }
        }
        .padding(.horizontal, 10)
    }
}
