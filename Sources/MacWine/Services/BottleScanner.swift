import Foundation

struct ScannedApp: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
}

/// Scans a bottle's Program Files for installed `.exe` apps the user can import.
enum BottleScanner {
    private static let skip = ["unins", "setup", "vcredist", "redist", "crashpad",
                               "helper", "update", "report", "notification", "service",
                               "dxsetup", "directx", "uninstall"]

    static func scan(prefix: URL) -> [ScannedApp] {
        let fm = FileManager.default
        let roots = ["drive_c/Program Files", "drive_c/Program Files (x86)"]
            .map { prefix.appendingPathComponent($0) }
        var seen = Set<String>()
        var found: [ScannedApp] = []

        for root in roots where fm.fileExists(atPath: root.path) {
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [.skipsHiddenFiles]) else { continue }
            var scanned = 0
            for case let f as URL in en {
                scanned += 1
                if scanned > 6000 { break }
                guard f.pathExtension.lowercased() == "exe" else { continue }
                let lower = f.lastPathComponent.lowercased()
                if skip.contains(where: { lower.contains($0) }) { continue }
                let depth = f.path.replacingOccurrences(of: root.path, with: "")
                    .split(separator: "/").count
                if depth > 6 { continue }
                if seen.insert(f.path).inserted {
                    found.append(ScannedApp(name: f.deletingPathExtension().lastPathComponent, path: f.path))
                }
            }
        }
        return found.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
