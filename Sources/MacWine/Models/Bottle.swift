import Foundation

/// A Wine bottle = an isolated WINEPREFIX directory.
struct Bottle: Identifiable, Codable, Equatable {
    var id: String              // also the prefix folder name, e.g. "win10-x64"
    var label: String           // "Windows 10 · x64"
    var wineVersion: String     // informational, e.g. "9.0"

    var shortLabel: String { label.components(separatedBy: " · ").first ?? label }
}

extension Bottle {
    static let defaults: [Bottle] = [
        .init(id: "win10-x64", label: "Windows 10 · x64", wineVersion: "9.0")
    ]
}
