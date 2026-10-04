import PitwallCore
import AppKit
import SwiftUI

/// Design tokens. One warm accent; semantic colours only for CI and review state.
enum Theme {
    // MARK: Colour

    /// Warm orange accent, a touch deeper in light mode for contrast.
    static let accent = Color(light: NSColor(srgbRed: 0.91, green: 0.38, blue: 0.13, alpha: 1),
                              dark: NSColor(srgbRed: 1.00, green: 0.47, blue: 0.22, alpha: 1))
    /// Accent for text on light backgrounds (meets 4.5:1 on white).
    static let accentText = Color(light: NSColor(srgbRed: 0.72, green: 0.27, blue: 0.05, alpha: 1),
                                  dark: NSColor(srgbRed: 1.00, green: 0.56, blue: 0.33, alpha: 1))

    static let success = Color(nsColor: .systemGreen)
    static let failure = Color(nsColor: .systemRed)
    /// Amber; darker in light mode so "CI running" text stays readable on white.
    static let pending = Color(light: NSColor(srgbRed: 0.70, green: 0.47, blue: 0.0, alpha: 1), dark: .systemYellow)
    static let merged = Color(nsColor: .systemPurple)

    /// The Codex mark colour on the timeline: near-white in dark, near-black in light.
    static let codex = Color(light: NSColor(white: 0.16, alpha: 1), dark: NSColor(white: 0.93, alpha: 1))

    static let hairline = Color(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.09))
    static let strongHairline = Color(light: NSColor(white: 0, alpha: 0.14), dark: NSColor(white: 1, alpha: 0.14))

    /// Raised surface for cards on the content panel.
    static func cardFill(hovered: Bool = false, reduceTransparency: Bool) -> Color {
        if reduceTransparency {
            return Color(light: NSColor(white: hovered ? 0.95 : 0.97, alpha: 1),
                         dark: NSColor(white: hovered ? 0.20 : 0.17, alpha: 1))
        }
        return Color(light: NSColor(white: 1, alpha: hovered ? 0.95 : 0.78),
                     dark: NSColor(white: 1, alpha: hovered ? 0.085 : 0.055))
    }

    /// The inset content panel that sits on the window material.
    static func panelFill(reduceTransparency: Bool) -> Color {
        if reduceTransparency {
            return Color(light: NSColor(white: 0.985, alpha: 1), dark: NSColor(white: 0.115, alpha: 1))
        }
        return Color(light: NSColor(white: 0.99, alpha: 0.72), dark: NSColor(srgbRed: 0.07, green: 0.065, blue: 0.06, alpha: 0.72))
    }

    // MARK: Shape

    static let cardRadius: CGFloat = 12
    static let panelRadius: CGFloat = 16
    static let controlRadius: CGFloat = 9

    // MARK: Type

    /// Small monospaced label (branches, counts, timestamps).
    static let mono = Font.system(.caption, design: .monospaced)
    static let monoSmall = Font.system(.caption2, design: .monospaced)
    static let monoMedium = Font.system(.caption, design: .monospaced).weight(.medium)
    static let largeTitle = Font.system(size: 28, weight: .semibold)
    static let sectionLabel = Font.system(.caption, design: .monospaced)

    // MARK: Motion

    static func animation(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28)
    }
}

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil ? dark : light
        })
    }
}

// MARK: - Semantics

// MARK: - Formatting
