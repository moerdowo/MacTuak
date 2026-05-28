import Foundation

/// A Wine bottle = an isolated WINEPREFIX directory.
struct Bottle: Identifiable, Codable, Equatable {
    var id: String              // also the prefix folder name, e.g. "win10-x64"
    var label: String           // "Windows 10 · x64"
    var wineVersion: String     // informational, e.g. "9.0"
    var windowsVersion: String? = nil   // win7 / win10 / win11
    var arch: String? = nil             // win32 / win64

    var shortLabel: String { label.components(separatedBy: " · ").first ?? label }
    var winVersion: String { windowsVersion ?? "win10" }
    /// The Wine arch to actually use. Pinned to win64 because the bundled Wine
    /// is wow64 (modern Wine has no pure-32-bit mode); WoW64 still runs 32-bit
    /// Windows apps inside a 64-bit prefix.
    var winArch: String { "win64" }

    var windowsVersionLabel: String {
        ["win7": "Windows 7", "win10": "Windows 10", "win11": "Windows 11"][winVersion] ?? winVersion
    }
}

extension Bottle {
    static let defaults: [Bottle] = [
        .init(id: "win10-x64", label: "Windows 10 · x64", wineVersion: "9.0", windowsVersion: "win10", arch: "win64")
    ]

    static let windowsVersionOptions = ["win7", "win10", "win11"]
    static let archOptions = ["win64", "win32"]
}
