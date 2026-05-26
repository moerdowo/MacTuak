import Foundation
import Combine

/// Live state for one launch — the LaunchOverlay binds to this and shows the
/// real stdout/stderr stream coming back from Wine.
@MainActor
final class LaunchSession: ObservableObject {
    enum Phase { case booting, running, exited, error }

    let app: WineApp
    @Published var lines: [String] = []
    @Published var phase: Phase = .booting

    private var buffer = ""

    init(app: WineApp) { self.app = app }

    func ingest(_ text: String) {
        buffer += text
        while let nl = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<nl])
            buffer.removeSubrange(buffer.startIndex...nl)
            append(line)
        }
        if phase == .booting { phase = .running }
    }

    func append(_ line: String) {
        lines.append(line)
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
    }

    func flush() {
        if !buffer.isEmpty { append(buffer); buffer = "" }
    }
}

/// Discovers a real Wine binary on the system and runs Windows executables
/// inside per-bottle WINEPREFIX sandboxes.
@MainActor
final class WineManager: ObservableObject {
    @Published var winePath: String?
    @Published var wineVersion: String = "Detecting…"
    @Published var installed = false

    private var processes: [String: Process] = [:]

    init() { detect() }

    // MARK: - Bottles (WINEPREFIX directories)

    var bottlesDirectory: URL {
        LibraryStore.supportDirectory.appendingPathComponent("Bottles", isDirectory: true)
    }
    func prefixURL(for bottle: String) -> URL {
        bottlesDirectory.appendingPathComponent(bottle, isDirectory: true)
    }

    // MARK: - Detection

    func detect() {
        Task.detached(priority: .utility) {
            let found = Self.locateWine()
            await MainActor.run {
                if let (path, version) = found {
                    self.winePath = path
                    self.wineVersion = version
                    self.installed = true
                } else {
                    self.winePath = nil
                    self.wineVersion = "Not installed"
                    self.installed = false
                }
            }
        }
    }

    nonisolated private static func candidatePaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin/wine", "/opt/homebrew/bin/wine64", "/opt/homebrew/bin/wine-stable",
            "/usr/local/bin/wine", "/usr/local/bin/wine64", "/usr/local/bin/wine-stable",
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64",
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine",
            "/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine64",
            "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine64",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
            "\(home)/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64",
            "\(home)/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine",
        ]
    }

    /// Returns (binaryPath, versionString) or nil. Runs off the main actor.
    nonisolated static func locateWine() -> (String, String)? {
        let fm = FileManager.default
        var candidates = candidatePaths()

        // Also honor anything reachable on PATH.
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                candidates.append("\(dir)/wine")
                candidates.append("\(dir)/wine64")
            }
        }

        for p in candidates where fm.isExecutableFile(atPath: p) {
            if let v = versionString(of: p) { return (p, v) }
        }
        return nil
    }

    nonisolated private static func versionString(of binary: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["--version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        // "wine-9.0 (Staging)" → "9.0-staging" style, but keep readable.
        return raw.replacingOccurrences(of: "wine-", with: "Wine ")
    }

    // MARK: - Launch

    func launch(app: WineApp, admin: Bool, library: LibraryStore) -> LaunchSession {
        let session = LaunchSession(app: app)

        guard let wine = winePath else {
            session.phase = .error
            session.append("$ wine \"\(app.name).exe\"")
            session.append("error: no Wine runtime found on this Mac.")
            session.append("")
            session.append("Install one of:")
            session.append("  • brew install --cask wine-stable")
            session.append("  • Whisky  (https://getwhisky.app)")
            session.append("  • CrossOver")
            session.append("then reopen MacWine — it will be detected automatically.")
            return session
        }

        let prefix = prefixURL(for: app.bottle)
        try? FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)

        // Resolve the executable: a folder drop runs the first .exe inside it.
        let target = resolveExecutable(app.exePath)

        session.append("$ \(wine) --version")
        session.append(wineVersion)
        session.append("$ WINEPREFIX=\(prefix.path) \\")
        session.append("  wine \"\(target ?? app.exePath)\"\(admin ? "  # elevated" : "")")

        guard let target, FileManager.default.fileExists(atPath: target) else {
            session.phase = .error
            session.append("error: executable not found at \(app.exePath)")
            return session
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: wine)
        proc.arguments = [target]

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        let wineBin = (wine as NSString).deletingLastPathComponent
        env["PATH"] = "\(wineBin):/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        proc.environment = env
        proc.currentDirectoryURL = URL(fileURLWithPath: (target as NSString).deletingLastPathComponent)

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in session.ingest(text) }
        }

        proc.terminationHandler = { _ in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                session.flush()
                session.append("→ \(app.name) exited.")
                session.phase = .exited
                library.setRunning(app.id, false)
                self.processes[app.id] = nil
            }
        }

        do {
            try proc.run()
            processes[app.id] = proc
            library.setRunning(app.id, true)
            // Give the boot badge a brief moment even if output is instant.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                if session.phase == .booting { session.phase = .running }
            }
        } catch {
            session.phase = .error
            session.append("error: failed to start Wine — \(error.localizedDescription)")
        }

        return session
    }

    func terminate(appID: String, library: LibraryStore) {
        processes[appID]?.terminate()
        processes[appID] = nil
        library.setRunning(appID, false)
    }

    private func resolveExecutable(_ path: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return path }
        if !isDir.boolValue { return path }
        // Folder: pick the first .exe inside (shallow scan).
        let url = URL(fileURLWithPath: path)
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.pathExtension.lowercased() == "exe" }?.path
    }
}
