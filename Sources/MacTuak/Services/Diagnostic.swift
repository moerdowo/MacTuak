import Foundation

/// Self-checks the runtime + active bottle. Output is plain text the user can
/// paste somewhere so we don't have to play 20 questions over a screenshot.
enum Diagnostic {
    struct Item: Identifiable, Sendable {
        enum Status: Sendable { case ok, warn, fail, info }
        let id = UUID()
        let title: String
        let status: Status
        let detail: String
    }

    @MainActor
    static func run(wine: WineManager, library: LibraryStore) async -> [Item] {
        var out: [Item] = []

        // System
        let macOS = ProcessInfo.processInfo.operatingSystemVersion
        out.append(Item(title: "macOS", status: .info,
                        detail: "\(macOS.majorVersion).\(macOS.minorVersion).\(macOS.patchVersion)"))

        // Wine runtime
        if let path = wine.winePath, FileManager.default.isExecutableFile(atPath: path) {
            let v = runOnce(path, "--version") ?? "(unknown)"
            out.append(Item(title: "Wine runtime", status: .ok,
                            detail: "engine=\(wine.engineID), version=\(v), binary=\(path)"))
        } else {
            out.append(Item(title: "Wine runtime", status: .fail,
                            detail: "winePath is empty — engine isn't installed or detection failed."))
        }

        // Bundled tools
        for t in ["cabextract", "7z"] {
            if let dir = wine.bundledToolsDir?.path,
               FileManager.default.isExecutableFile(atPath: "\(dir)/\(t)") {
                out.append(Item(title: "Bundled \(t)", status: .ok, detail: "\(dir)/\(t)"))
            } else {
                out.append(Item(title: "Bundled \(t)", status: .warn,
                                detail: "missing — winetricks will fall back to Homebrew."))
            }
        }

        // Bundled runtime libs
        let runtimeDir = WineManager.managedDir
        for lib in ["libinotify.0.dylib", "libfreetype.6.dylib"] {
            let url = runtimeDir.appendingPathComponent(lib)
            if FileManager.default.fileExists(atPath: url.path) {
                let arches = lipoArches(at: url.path) ?? "?"
                out.append(Item(title: "Shim \(lib)", status: .ok,
                                detail: "\(url.path) (arch: \(arches))"))
            } else {
                out.append(Item(title: "Shim \(lib)", status: .warn,
                                detail: "not next to wswine.bundle — bootstrap may not have copied it."))
            }
        }

        // DYLD_FALLBACK_LIBRARY_PATH would normally include the managed dir;
        // we set it per-launch, so just remind the user.
        out.append(Item(title: "DYLD_FALLBACK", status: .info,
                        detail: "Set per launch to \(runtimeDir.path):~/lib:/usr/local/lib:/usr/lib"))

        // Library + bottles
        out.append(Item(title: "Library", status: .info,
                        detail: "\(library.apps.count) apps, \(library.bottles.count) bottles"))

        for b in library.bottles {
            let prefix = wine.prefixURL(for: b.id)
            let exists = FileManager.default.fileExists(atPath: prefix.path)
            let sys32 = prefix.appendingPathComponent("drive_c/windows/system32")
            let booted = FileManager.default.fileExists(atPath: sys32.path)
            let status: Item.Status = exists && booted ? .ok : (exists ? .warn : .fail)
            let note: String
            if !exists { note = "prefix missing — Bottle Manager → Initialize / Repair." }
            else if !booted { note = "no system32 — needs Initialize / Repair." }
            else { note = "OK · Windows=\(b.winVersion) · arch=\(b.winArch)" }
            out.append(Item(title: "Bottle \(b.shortLabel)", status: status, detail: note))

            // Stale wineserver check: is one running for this prefix?
            if let pid = wineserverPID(for: prefix) {
                out.append(Item(title: "wineserver in \(b.shortLabel)", status: .warn,
                                detail: "process \(pid) is running — Bottle Manager → Force Quit if you hit esync errors."))
            }
        }

        // Winetricks script
        let wt = LibraryStore.supportDirectory.appendingPathComponent("winetricks")
        if FileManager.default.isExecutableFile(atPath: wt.path) {
            out.append(Item(title: "winetricks script", status: .ok, detail: wt.path))
        } else {
            out.append(Item(title: "winetricks script", status: .info,
                            detail: "not yet downloaded; first install will fetch it."))
        }

        return out
    }

    static func formatted(_ items: [Item]) -> String {
        var lines: [String] = ["MacTuak diagnostic"]
        lines.append("==================")
        for it in items {
            let prefix: String
            switch it.status {
            case .ok: prefix = "[ OK ]"
            case .warn: prefix = "[WARN]"
            case .fail: prefix = "[FAIL]"
            case .info: prefix = "[INFO]"
            }
            lines.append("\(prefix) \(it.title): \(it.detail)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: helpers (nonisolated)

    private static func runOnce(_ executable: String, _ args: String...) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lipoArches(at path: String) -> String? {
        runOnce("/usr/bin/lipo", "-archs", path)
    }

    private static func wineserverPID(for prefix: URL) -> Int32? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-ax", "-o", "pid=,command="]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        for line in out.split(separator: "\n") {
            if line.contains("wineserver") && line.contains(prefix.path),
               let pidStr = line.split(separator: " ").first, let pid = Int32(pidStr) {
                return pid
            }
        }
        return nil
    }
}
