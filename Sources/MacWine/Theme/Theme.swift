import SwiftUI

// Hex color support so we can mirror the design's exact palette.
extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Darken toward black by `amount` (0…1) — matches the design's
    /// `color-mix(in oklab, accent X%, #000)` gradient stops.
    func darkened(_ amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return Color(.sRGB,
                     red: Double(ns.redComponent) * (1 - amount),
                     green: Double(ns.greenComponent) * (1 - amount),
                     blue: Double(ns.blueComponent) * (1 - amount),
                     opacity: 1)
    }
}

enum Theme {
    static let accentOptions = ["#0a84ff", "#ff375f", "#8B5CF6", "#30d158"]

    // Category accent dots — matches chrome.jsx CatDot.
    static let categoryColors: [String: Color] = [
        "Games": Color(hex: "#ff453a"),
        "Productivity": Color(hex: "#0a84ff"),
        "Creative": Color(hex: "#bf5af2"),
        "Media": Color(hex: "#ff9f0a"),
        "Developer": Color(hex: "#30d158"),
        "Utilities": Color(hex: "#64d2ff"),
    ]

    static let categories = ["All", "Games", "Productivity", "Creative", "Media", "Developer", "Utilities"]

    // Gradient palette pool used when auto-assigning icons to imported apps.
    static let iconGradients: [(String, String)] = [
        ("#8B5CF6", "#3B2A6B"), ("#5BA4F0", "#1E4E8C"), ("#6FCF7B", "#1F6F36"),
        ("#E8615A", "#7A1A14"), ("#F5C76D", "#9B5A12"), ("#6A4FE6", "#1A0A4A"),
        ("#4DA8FF", "#001E36"), ("#F08CC4", "#7A1F4F"), ("#3A6BA5", "#1B2838"),
        ("#9DE56A", "#3A9D2B"), ("#FFE066", "#E89C1F"), ("#E04A2B", "#3A0707"),
    ]

    static func gradient(for seed: String) -> (String, String) {
        let h = abs(seed.hashValue)
        return iconGradients[h % iconGradients.count]
    }
}

// MARK: - Opaque light/dark palette (no transparency)

struct Palette {
    let isDark: Bool
    let appBG: Color          // window root
    let sidebarBG: Color
    let contentBG: Color
    let bar: Color            // toolbar / status bar
    let card: Color           // app tiles, list container
    let control: Color        // search, segmented track, secondary buttons
    let controlActive: Color  // segmented thumb / hovered control
    let border: Color
    let separator: Color
    let text: Color
    let textSecondary: Color

    static func make(_ dark: Bool) -> Palette {
        if dark {
            return Palette(
                isDark: true,
                appBG: Color(hex: "#1b1b22"),
                sidebarBG: Color(hex: "#17171e"),
                contentBG: Color(hex: "#202028"),
                bar: Color(hex: "#1d1d25"),
                card: Color(hex: "#2a2a33"),
                control: Color(hex: "#2e2e38"),
                controlActive: Color(hex: "#3b3b47"),
                border: Color.white.opacity(0.09),
                separator: Color.white.opacity(0.08),
                text: Color.white.opacity(0.92),
                textSecondary: Color.white.opacity(0.55))
        } else {
            return Palette(
                isDark: false,
                appBG: Color(hex: "#e9eaf0"),
                sidebarBG: Color(hex: "#e6e7ee"),
                contentBG: Color(hex: "#f4f5f9"),
                bar: Color(hex: "#eef0f5"),
                card: Color(hex: "#ffffff"),
                control: Color(hex: "#ffffff"),
                controlActive: Color(hex: "#ffffff"),
                border: Color.black.opacity(0.10),
                separator: Color.black.opacity(0.07),
                text: Color.black.opacity(0.88),
                textSecondary: Color.black.opacity(0.5))
        }
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.make(false) }
extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Solid (opaque) rounded surface with a hairline border.
    func solidSurface<S: InsettableShape>(_ shape: S, _ p: Palette, fill: Color? = nil, border: Bool = true) -> some View {
        self.background(fill ?? p.control, in: shape)
            .overlay { if border { shape.strokeBorder(p.border, lineWidth: 0.5) } }
    }
}
