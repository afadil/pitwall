import AppKit
import SwiftUI

/// The app icon, drawn in SwiftUI so it can be regenerated with
/// `Pitwall --render-icon <folder>` (see Scripts/make-icon.sh).
/// Three kanban columns of soft pads, orange and white on charcoal.
struct IconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.21, blue: 0.19), Color(red: 0.085, green: 0.075, blue: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 3)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)

            HStack(alignment: .top, spacing: 36) {
                column([.orange, .orange, .dim])
                column([.white, .white])
                column([.orange])
            }
            .frame(width: 824, height: 824, alignment: .top)
            .padding(.top, 236)

            // Step strip, like the sequencer's playhead row.
            HStack(spacing: 14) {
                ForEach(0..<8, id: \.self) { index in
                    Capsule()
                        .fill(index == 2 ? AnyShapeStyle(orange) : AnyShapeStyle(Color.white.opacity(0.12)))
                        .frame(width: 58, height: 16)
                }
            }
            .offset(y: 300)
        }
        .frame(width: 1024, height: 1024)
    }

    private enum PadKind { case orange, white, dim }

    private var orange: LinearGradient {
        LinearGradient(colors: [Color(red: 1.0, green: 0.56, blue: 0.30), Color(red: 0.93, green: 0.38, blue: 0.12)], startPoint: .top, endPoint: .bottom)
    }

    private func column(_ pads: [PadKind]) -> some View {
        VStack(spacing: 30) {
            ForEach(Array(pads.enumerated()), id: \.offset) { _, kind in
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(fill(kind))
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .strokeBorder(.white.opacity(kind == .dim ? 0.08 : 0.35), lineWidth: 2)
                    )
                    .frame(width: 168, height: 128)
                    .shadow(color: shadow(kind), radius: 16, y: 6)
            }
        }
    }

    private func fill(_ kind: PadKind) -> AnyShapeStyle {
        switch kind {
        case .orange: AnyShapeStyle(orange)
        case .white: AnyShapeStyle(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
        case .dim: AnyShapeStyle(Color(red: 0.42, green: 0.25, blue: 0.17).opacity(0.75))
        }
    }

    private func shadow(_ kind: PadKind) -> Color {
        switch kind {
        case .orange: Color(red: 1, green: 0.45, blue: 0.15).opacity(0.45)
        case .white: .white.opacity(0.18)
        case .dim: .clear
        }
    }

    /// Writes `icon_1024.png` into `folder`.
    @MainActor
    static func render(to folder: URL) throws {
        let renderer = ImageRenderer(content: IconArt())
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appending(path: "icon_1024.png"))
    }
}
