import SwiftUI
import AppKit

extension Color {
    /// Light/dark dynamic color from hex strings.
    init(light: String, dark: String) {
        self.init(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    /// Initialize from "#RRGGBB" or "RRGGBB".
    convenience init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green:   CGFloat((rgb >> 8)  & 0xFF) / 255,
                  blue:    CGFloat(rgb         & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Status palette
//
// Sage / Honey / Terracotta — earthy, low-saturation, artistic.
// Avoids the generic "system green/orange/red" look while keeping
// quick visual recognition for safe / warn / danger states.

extension Color {
    static let statusSafe   = Color(light: "#7A9B76", dark: "#9CAF88")
    static let statusWarn   = Color(light: "#C89B6E", dark: "#D4A574")
    static let statusDanger = Color(light: "#B56555", dark: "#C87361")
}
