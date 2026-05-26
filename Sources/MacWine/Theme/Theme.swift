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

struct WallpaperSpec {
    let base: [Color]          // gradient stops, top-left → bottom-right
    let blobs: [Blob]
    struct Blob { let x, y, r, o: Double; let c: Color }
}

let WALLPAPERS: [String: WallpaperSpec] = [
    "sunset": WallpaperSpec(
        base: [Color(hex: "#ff7a59"), Color(hex: "#ff5e87"), Color(hex: "#b14df2"), Color(hex: "#4f3bdd")],
        blobs: [
            .init(x: 8,  y: 12, r: 38, o: 0.55, c: Color(hex: "#ffd166")),
            .init(x: 78, y: 22, r: 32, o: 0.70, c: Color(hex: "#ff5e87")),
            .init(x: 18, y: 78, r: 44, o: 0.60, c: Color(hex: "#8c52ff")),
            .init(x: 86, y: 78, r: 28, o: 0.45, c: Color(hex: "#22d3ee")),
        ]),
    "ocean": WallpaperSpec(
        base: [Color(hex: "#00d4ff"), Color(hex: "#2a78ff"), Color(hex: "#4f3bdd"), Color(hex: "#2a1f6b")],
        blobs: [
            .init(x: 10, y: 18, r: 36, o: 0.55, c: Color(hex: "#5eead4")),
            .init(x: 82, y: 28, r: 30, o: 0.50, c: Color(hex: "#a78bfa")),
            .init(x: 22, y: 80, r: 40, o: 0.55, c: Color(hex: "#3b82f6")),
            .init(x: 88, y: 82, r: 28, o: 0.40, c: Color(hex: "#ec4899")),
        ]),
    "forest": WallpaperSpec(
        base: [Color(hex: "#fef9c3"), Color(hex: "#84cc16"), Color(hex: "#14b8a6"), Color(hex: "#0f3460")],
        blobs: [
            .init(x: 12, y: 16, r: 36, o: 0.60, c: Color(hex: "#fde047")),
            .init(x: 80, y: 22, r: 32, o: 0.55, c: Color(hex: "#22c55e")),
            .init(x: 20, y: 78, r: 42, o: 0.50, c: Color(hex: "#0ea5e9")),
            .init(x: 86, y: 80, r: 26, o: 0.45, c: Color(hex: "#a3e635")),
        ]),
    "graphite": WallpaperSpec(
        base: [Color(hex: "#2a2a32"), Color(hex: "#1a1a22"), Color(hex: "#0f0f17")],
        blobs: [
            .init(x: 14, y: 18, r: 38, o: 0.45, c: Color(hex: "#7c3aed")),
            .init(x: 82, y: 28, r: 30, o: 0.40, c: Color(hex: "#06b6d4")),
            .init(x: 22, y: 80, r: 40, o: 0.40, c: Color(hex: "#ec4899")),
            .init(x: 86, y: 82, r: 26, o: 0.35, c: Color(hex: "#22c55e")),
        ]),
]
