import PitwallCore
import SwiftUI

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
