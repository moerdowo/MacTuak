import Foundation

struct SteamGame: Identifiable, Hashable {
    var id: String { exePath }
    let game: String      // game folder name
    let exePath: String   // chosen .exe
    let library: String   // which library root
}

/// Finds Windows games inside the user's Steam libraries by scanning each
/// `steamapps/common/<Game>/` folder for `.exe` files. Native macOS games
/// (Mach-O only) are filtered out implicitly.
enum SteamScanner {
    private static let skipNames: Set<String> = [
        "unins", "setup", "vcredist", "redist", "crashpad", "helper",
        "report", "service", "uninstall", "dxsetup", "directx", "lobby",
    ]

    static func discoverLibraries() -> [URL] {
        var libs: [URL] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultRoot = home.appendingPathComponent("Library/Application Support/Steam/steamapps")
        if FileManager.default.fileExists(atPath: defaultRoot.path) { libs.append(defaultRoot) }

        // Parse libraryfolders.vdf for extra mount points.
        let vdf = defaultRoot.appendingPathComponent("libraryfolders.vdf")
        if let text = try? String(contentsOf: vdf, encoding: .utf8) {
            // Lines look like:    "path"   "/Volumes/Games/SteamLibrary"
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("\"path\"") else { continue }
                // "path" "..."
                if let firstQ = t.range(of: "\"", range: t.range(of: "\"path\"")!.upperBound..<t.endIndex),
                   let secondQ = t.range(of: "\"", range: firstQ.upperBound..<t.endIndex) {
                    let path = String(t[firstQ.upperBound..<secondQ.lowerBound])
                    let url = URL(fileURLWithPath: path).appendingPathComponent("steamapps")
                    if FileManager.default.fileExists(atPath: url.path), !libs.contains(url) {
                        libs.append(url)
                    }
                }
            }
        }
        return libs
    }

    static func scan() -> [SteamGame] {
        var results: [SteamGame] = []
        let fm = FileManager.default
        for libRoot in discoverLibraries() {
            let common = libRoot.appendingPathComponent("common")
            guard let games = try? fm.contentsOfDirectory(at: common,
                                                          includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { continue }
            for gameDir in games {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: gameDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                if let exe = findMainExe(in: gameDir) {
                    results.append(SteamGame(game: gameDir.lastPathComponent,
                                              exePath: exe,
                                              library: libRoot.path))
                }
            }
        }
        return results.sorted { $0.game.lowercased() < $1.game.lowercased() }
    }

    /// Picks the most-likely "main" .exe: largest file at depth ≤2, with a
    /// name that doesn't look like an installer/helper.
    private static func findMainExe(in dir: URL) -> String? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey],
                                     options: [.skipsHiddenFiles]) else { return nil }
        var best: (path: String, size: Int64) = ("", 0)
        var scanned = 0
        for case let f as URL in en {
            scanned += 1
            if scanned > 4000 { break }
            guard f.pathExtension.lowercased() == "exe" else { continue }
            let lower = f.lastPathComponent.lowercased()
            if skipNames.contains(where: { lower.contains($0) }) { continue }
            // Depth check
            let rel = f.path.dropFirst(dir.path.count)
            if rel.split(separator: "/").count > 4 { continue }
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if Int64(size) > best.size {
                best = (f.path, Int64(size))
            }
        }
        return best.path.isEmpty ? nil : best.path
    }
}
