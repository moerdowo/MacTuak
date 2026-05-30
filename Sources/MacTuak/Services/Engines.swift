import Foundation

/// A selectable Wine engine. Each engine knows where to fetch its build from.
struct WineEngine: Identifiable, Hashable, Sendable {
    let id: String           // stable identifier persisted in Settings
    let name: String         // display name
    let description: String  // one-liner shown in the picker
    let badge: String?       // small tag like "Default" / "Games" / "GPTK" / "32-bit"
    let approxSizeMB: Int    // download size hint (informational)
    let kind: Kind

    enum Kind: Hashable, Sendable {
        /// Gcenx/macOS_Wine_builds: latest release whose asset name starts with
        /// `wine-<channel>-` and ends with `-osx64.tar.xz`.
        case gcenx(channel: String)
        /// Sikarugir-App/Engines: a single release with many tarballs; pick the
        /// newest asset whose name starts with `prefix` and ends with `.tar.xz`.
        case sikarugir(prefix: String)
    }
}

enum WineEngines {
    static let catalog: [WineEngine] = [
        .init(id: "sikarugir-cx", name: "WineCX (CrossOver)",
              description: "CrossOver's Wine. Strongest general game compatibility on macOS.",
              badge: "Default", approxSizeMB: 220, kind: .sikarugir(prefix: "WS12WineCX")),
        .init(id: "gcenx-stable", name: "Gcenx Stable",
              description: "Vanilla Wine, broadest compatibility for everyday apps.",
              badge: nil, approxSizeMB: 185, kind: .gcenx(channel: "stable")),
        .init(id: "gcenx-staging", name: "Gcenx Staging",
              description: "Wine staging — newer patches; helps with stubborn installers.",
              badge: nil, approxSizeMB: 190, kind: .gcenx(channel: "staging")),
        .init(id: "gcenx-devel", name: "Gcenx Devel",
              description: "Bleeding-edge Wine; least stable.",
              badge: nil, approxSizeMB: 190, kind: .gcenx(channel: "devel")),
        .init(id: "sikarugir-gptk", name: "Wine GPTK",
              description: "Apple's Game Porting Toolkit — best D3D11/12 layer for modern games.",
              badge: "GPTK", approxSizeMB: 230, kind: .sikarugir(prefix: "WS12WineGPTK")),
        .init(id: "sikarugir-whisky", name: "Whisky Wine",
              description: "Whisky's curated build with macOS patches.",
              badge: "Whisky", approxSizeMB: 200, kind: .sikarugir(prefix: "WS12WhiskyWine")),
        .init(id: "sikarugir-sikarugir", name: "Wine Sikarugir",
              description: "Sikarugir's own curated Wine.",
              badge: nil, approxSizeMB: 200, kind: .sikarugir(prefix: "WS12WineSikarugir")),
        .init(id: "sikarugir-cx32", name: "WineCX 32-bit",
              description: "True 32-bit prefixes (no wow64). Use this for old InstallShield setups that fail on modern Wine.",
              badge: "32-bit", approxSizeMB: 110, kind: .sikarugir(prefix: "WS11WineCX32Bit")),
    ]

    static func find(_ id: String) -> WineEngine? { catalog.first { $0.id == id } }
    static var defaultEngine: WineEngine { catalog.first! }
}
