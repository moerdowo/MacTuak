import Foundation

/// Per-app launch configuration.
struct LaunchOptions: Codable, Equatable {
    var arguments: String = ""
    var workingDir: String = ""
    var environment: String = ""    // "KEY=VALUE" per line
    var winedebug: String = ""      // e.g. "-all" to silence, "" for default
    var esync: Bool = false  // opt-in perf toggle; many wine builds bail when wineserver wasn't started with it
    var retina: Bool = false
    var virtualDesktop: String = "" // "" = off, else "1280x720"
}

/// A Windows application registered in the library. Persisted to JSON.
struct WineApp: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var publisher: String
    var version: String
    var bottle: String          // bottle id (WINEPREFIX name)
    var arch: String            // "x64" / "x86"
    var sizeBytes: Int64
    var category: String
    var glyph: String
    var g1: String              // gradient hex top
    var g2: String              // gradient hex bottom
    var favorite: Bool
    var exePath: String         // absolute path to the .exe (or folder)
    var lastRun: Date?
    var iconFileName: String? = nil   // optional custom icon stored in Icons/
    var options: LaunchOptions? = nil // optional for back-compat
    var addedAt: Date? = nil
    var engineID: String? = nil       // optional per-app wine engine override

    // Transient — not persisted; reflects live process state.
    var running: Bool = false

    /// Effective launch options (never nil at use sites).
    var opts: LaunchOptions {
        get { options ?? LaunchOptions() }
        set { options = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, publisher, version, bottle, arch, sizeBytes
        case category, glyph, g1, g2, favorite, exePath, lastRun, iconFileName
        case options, addedAt, engineID
    }

    static var iconsDirectory: URL {
        LibraryStore.supportDirectory.appendingPathComponent("Icons", isDirectory: true)
    }
    var iconURL: URL? { iconFileName.map { Self.iconsDirectory.appendingPathComponent($0) } }

    var sizeDisplay: String { Self.humanSize(sizeBytes) }

    var lastRunDisplay: String {
        guard let d = lastRun else { return "Never" }
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "Just now" }
        if s < 3600 { let m = Int(s / 60); return "\(m) min ago" }
        if s < 7200 { return "An hour ago" }
        if s < 86400 { let h = Int(s / 3600); return "\(h) hours ago" }
        if s < 172800 { return "Yesterday" }
        if s < 604800 { let dd = Int(s / 86400); return "\(dd) days ago" }
        if s < 2_592_000 { let w = Int(s / 604800); return w == 1 ? "1 week ago" : "\(w) weeks ago" }
        let mo = Int(s / 2_592_000)
        return mo == 1 ? "1 month ago" : "\(mo) months ago"
    }

    /// Rough recency score for the "Recent" smart group (lower = more recent).
    var recencyScore: TimeInterval { lastRun.map { -$0.timeIntervalSince1970 } ?? .greatestFiniteMagnitude }

    static func humanSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "— MB" }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    /// Build a library entry from a dropped/picked file or folder.
    static func imported(from url: URL, bottle: String) -> WineApp {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        let rawName = url.deletingPathExtension().lastPathComponent
        let display = rawName.isEmpty ? url.lastPathComponent : rawName
        let glyphSrc = display.replacingOccurrences(of: " ", with: "")
        let glyph = String(glyphSrc.prefix(2)).uppercased()
        let (g1, g2) = Theme.gradient(for: display)

        let size: Int64
        if isDir.boolValue {
            size = directorySize(url)
        } else {
            size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }

        return WineApp(
            id: "app-\(UUID().uuidString.prefix(8))",
            name: display,
            publisher: "Imported",
            version: "—",
            bottle: bottle,
            arch: "x64",
            sizeBytes: size,
            category: "Utilities",
            glyph: glyph.isEmpty ? "EX" : glyph,
            g1: g1, g2: g2,
            favorite: false,
            exePath: url.path,
            lastRun: nil,
            addedAt: Date()
        )
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            let vals = try? f.resourceValues(forKeys: keys)
            total += Int64(vals?.totalFileAllocatedSize ?? vals?.fileAllocatedSize ?? 0)
        }
        return total
    }
}
