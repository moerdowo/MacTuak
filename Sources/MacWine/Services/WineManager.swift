import Foundation
import Combine
import AppKit

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

/// Generic streaming console for bottle tools (wineboot, winetricks, winecfg…).
@MainActor
final class ConsoleSession: ObservableObject, Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    @Published var lines: [String] = []
    @Published var phase: LaunchSession.Phase = .booting
    private var buffer = ""

    init(title: String, subtitle: String) { self.title = title; self.subtitle = subtitle }

    func ingest(_ text: String) {
        buffer += text
        while let nl = buffer.firstIndex(of: "\n") {
            append(String(buffer[buffer.startIndex..<nl]))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        if phase == .booting { phase = .running }
    }
    func append(_ line: String) { lines.append(line); if lines.count > 600 { lines.removeFirst(lines.count - 600) } }
    func flush() { if !buffer.isEmpty { append(buffer); buffer = "" } }
}

// MARK: - Runtime state (surfaced in the status bar / tweaks)

struct RuntimeState: Equatable, Sendable {
    enum Kind: Sendable { case detecting, needsDownload, downloading, extracting, installing, ready, systemFallback, failed }
    var kind: Kind = .detecting
    var version: String = ""
    var progress: Double = 0
    var detail: String = ""

    var statusText: String {
        switch kind {
        case .detecting:      return "Checking Wine runtime…"
        case .needsDownload:  return "Preparing Wine download…"
        case .downloading:    return "Downloading Wine \(version) · \(Int(progress * 100))%"
        case .extracting:     return "Extracting Wine \(version)…"
        case .installing:     return "Installing Wine \(version)…"
        case .ready:          return "Wine \(version)"
        case .systemFallback: return "Wine \(version) (system)"
        case .failed:         return detail.isEmpty ? "Wine setup failed" : detail
        }
    }
    var isBusy: Bool { kind == .downloading || kind == .extracting || kind == .installing }
    var isWarning: Bool { kind == .failed || kind == .needsDownload || kind == .systemFallback }
}

private struct InstalledInfo: Codable, Sendable {
    var version: String
    var binary: String
    var channel: String? = nil
}

/// Manages a self-updating, app-owned (bundled) stable Wine runtime and runs
/// Windows executables inside per-bottle WINEPREFIX sandboxes.
@MainActor
final class WineManager: ObservableObject {
    @Published var runtime = RuntimeState()
    @Published var winePath: String?

    private var activeVersion = ""
    private var activeIsSystem = false
    private var processes: [String: Process] = [:]
    private var watchers: [String: Process] = [:]

    /// Wine channel to track (stable/staging/devel). Set from Settings.
    var channel = "stable"

    init() { bootstrap() }

    var logsDirectory: URL { LibraryStore.supportDirectory.appendingPathComponent("Logs", isDirectory: true) }

    // MARK: - Paths

    nonisolated static var managedDir: URL {
        LibraryStore.supportDirectory.appendingPathComponent("Wine", isDirectory: true)
    }
    nonisolated static var infoURL: URL {
        managedDir.appendingPathComponent("installed.json")
    }
    var bottlesDirectory: URL {
        LibraryStore.supportDirectory.appendingPathComponent("Bottles", isDirectory: true)
    }
    func prefixURL(for bottle: String) -> URL {
        bottlesDirectory.appendingPathComponent(bottle, isDirectory: true)
    }

    nonisolated private static func loadInfo() -> InstalledInfo? {
        guard let data = try? Data(contentsOf: infoURL) else { return nil }
        return try? JSONDecoder().decode(InstalledInfo.self, from: data)
    }
    nonisolated private static func saveInfo(_ info: InstalledInfo) {
        if let data = try? JSONEncoder().encode(info) { try? data.write(to: infoURL, options: .atomic) }
    }

    // MARK: - Bootstrap & update

    func bootstrap() {
        Task.detached(priority: .utility) {
            if let info = Self.loadInfo(), FileManager.default.isExecutableFile(atPath: info.binary) {
                await self.setActive(path: info.binary, version: info.version, system: false, kind: .ready)
            } else if let sys = Self.locateWine() {
                await self.setActive(path: sys.0, version: sys.1, system: true, kind: .systemFallback)
            } else {
                await MainActor.run { self.runtime = RuntimeState(kind: .detecting) }
            }
            await self.checkForUpdate(force: false)
        }
    }

    /// Checks the latest stable Gcenx release and installs it if newer (or if no
    /// runtime is present). `force` re-confirms even when already up to date.
    func checkForUpdate(force: Bool) {
        guard !runtime.isBusy else { return }
        let haveActive = winePath != nil
        let currentInfo = Self.loadInfo()
        let channel = self.channel

        Task.detached(priority: .utility) {
            do {
                let release = try await WineInstaller.latest(channel: channel)

                // Already on the latest managed build for this channel?
                if let info = currentInfo, info.version == release.version, (info.channel ?? "stable") == channel,
                   FileManager.default.isExecutableFile(atPath: info.binary) {
                    await self.setActive(path: info.binary, version: info.version, system: false, kind: .ready)
                    return
                }

                await MainActor.run { self.runtime = RuntimeState(kind: .downloading, version: release.version, progress: 0) }
                let archive = try await WineInstaller.download(from: release.url) { frac in
                    Task { @MainActor in self.updateProgress(frac) }
                }

                await MainActor.run { self.runtime = RuntimeState(kind: .extracting, version: release.version) }
                let staging = FileManager.default.temporaryDirectory
                    .appendingPathComponent("macwine-stage-\(UUID().uuidString)", isDirectory: true)
                try WineInstaller.extract(archive, into: staging)
                guard WineInstaller.findWineBinary(in: staging) != nil else {
                    throw NSError(domain: "MacWine", code: 3, userInfo: [NSLocalizedDescriptionKey: "No wine binary in archive"])
                }

                await MainActor.run { self.runtime = RuntimeState(kind: .installing, version: release.version) }
                let fm = FileManager.default
                try? fm.removeItem(at: Self.managedDir)
                try fm.createDirectory(at: Self.managedDir.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: staging, to: Self.managedDir)
                guard let bin = WineInstaller.findWineBinary(in: Self.managedDir) else {
                    throw NSError(domain: "MacWine", code: 4, userInfo: [NSLocalizedDescriptionKey: "wine binary missing after install"])
                }
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin)
                Self.saveInfo(InstalledInfo(version: release.version, binary: bin, channel: channel))
                try? fm.removeItem(at: archive)

                await self.setActive(path: bin, version: release.version, system: false, kind: .ready)
            } catch {
                await self.handleUpdateFailure(error.localizedDescription, haveActive: haveActive)
            }
        }
    }

    private func setActive(path: String, version: String, system: Bool, kind: RuntimeState.Kind) {
        winePath = path
        activeVersion = version
        activeIsSystem = system
        runtime = RuntimeState(kind: kind, version: version)
    }

    private func updateProgress(_ frac: Double) {
        if runtime.kind == .downloading { runtime.progress = frac }
    }

    private func handleUpdateFailure(_ message: String, haveActive: Bool) {
        if winePath != nil {
            runtime = RuntimeState(kind: activeIsSystem ? .systemFallback : .ready, version: activeVersion, detail: message)
        } else {
            runtime = RuntimeState(kind: .failed, detail: "Wine download failed — \(message)")
        }
    }

    // MARK: - System Wine detection (fallback)

    nonisolated private static func candidatePaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin/wine", "/opt/homebrew/bin/wine64", "/opt/homebrew/bin/wine-stable",
            "/usr/local/bin/wine", "/usr/local/bin/wine64", "/usr/local/bin/wine-stable",
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64",
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine",
            "/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine64",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
            "\(home)/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64",
        ]
    }

    nonisolated static func locateWine() -> (String, String)? {
        let fm = FileManager.default
        var candidates = candidatePaths()
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") { candidates.append("\(dir)/wine"); candidates.append("\(dir)/wine64") }
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
        do { try proc.run(); proc.waitUntilExit() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: "wine-", with: "")
    }

    // MARK: - Launch

    func launch(app: WineApp, admin: Bool, library: LibraryStore) -> LaunchSession {
        let session = LaunchSession(app: app)

        guard let wine = winePath else {
            session.phase = .error
            session.append("$ wine \"\(app.name).exe\"")
            if runtime.isBusy {
                session.append("Wine runtime is still being set up (\(runtime.statusText)).")
                session.append("Try again in a moment.")
            } else {
                session.append("error: Wine runtime is not available yet.")
                session.append(runtime.detail.isEmpty ? "Open Tweaks → Wine Runtime → Check for update." : runtime.detail)
            }
            return session
        }

        let prefix = prefixURL(for: app.bottle)
        try? FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let opts = app.opts
        let target = resolveExecutable(app.exePath)

        applyRetina(opts.retina, wine: wine, prefix: prefix)

        let isMSI = (target ?? app.exePath).lowercased().hasSuffix(".msi")
        var args: [String] = []
        if !opts.virtualDesktop.isEmpty { args += ["explorer", "/desktop=MacWine,\(opts.virtualDesktop)"] }
        if isMSI { args += ["msiexec", "/i", target ?? app.exePath] }
        else if let target { args += [target] }
        args += tokenize(opts.arguments)

        session.append("$ \(wine) --version")
        session.append("Wine \(activeVersion)")
        session.append("$ WINEPREFIX=\(prefix.path) \\")
        session.append("  wine \(args.map { "\"\($0)\"" }.joined(separator: " "))\(admin ? "  # elevated" : "")")

        guard let target, FileManager.default.fileExists(atPath: target) else {
            session.phase = .error
            session.append("error: executable not found at \(app.exePath)")
            return session
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: wine)
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        let wineBin = (wine as NSString).deletingLastPathComponent
        env["PATH"] = "\(wineBin):/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        env["WINEESYNC"] = opts.esync ? "1" : "0"
        if !opts.winedebug.isEmpty { env["WINEDEBUG"] = opts.winedebug }
        for line in opts.environment.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { env[kv[0].trimmingCharacters(in: .whitespaces)] = String(kv[1]) }
        }
        proc.environment = env
        let workDir = opts.workingDir.isEmpty
            ? (target as NSString).deletingLastPathComponent
            : (opts.workingDir as NSString).expandingTildeInPath
        proc.currentDirectoryURL = URL(fileURLWithPath: workDir)

        let wineserver = (wine as NSString).deletingLastPathComponent + "/wineserver"
        let hasWineserver = FileManager.default.isExecutableFile(atPath: wineserver)

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
                // The wine launcher returns as soon as the app is handed off to
                // wineserver — so only treat its exit as the app exiting when
                // there's no server to wait on (see watchAppExit).
                if !hasWineserver {
                    session.append("→ \(app.name) exited.")
                    session.phase = .exited
                    library.setRunning(app.id, false)
                    self.processes[app.id] = nil
                    self.writeLog(session, app: app)
                }
            }
        }

        do {
            try proc.run()
            processes[app.id] = proc
            library.setRunning(app.id, true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                if session.phase == .booting { session.phase = .running }
            }
            if hasWineserver {
                watchAppExit(app: app, wineserver: wineserver, prefix: prefix, session: session, library: library)
            }
        } catch {
            session.phase = .error
            session.append("error: failed to start Wine — \(error.localizedDescription)")
        }
        return session
    }

    /// Waits on `wineserver -w` — it returns only once every process in the prefix
    /// has quit — so the running indicator tracks the real Windows app rather than
    /// the short-lived wine launcher process.
    private func watchAppExit(app: WineApp, wineserver: String, prefix: URL, session: LaunchSession, library: LibraryStore) {
        Task { @MainActor in
            // Let the app register with the server before we start waiting.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let w = Process()
            w.executableURL = URL(fileURLWithPath: wineserver)
            w.arguments = ["-w"]
            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = prefix.path
            w.environment = env
            w.standardOutput = FileHandle.nullDevice
            w.standardError = FileHandle.nullDevice
            w.terminationHandler = { _ in
                Task { @MainActor in
                    session.append("→ \(app.name) exited.")
                    session.phase = .exited
                    library.setRunning(app.id, false)
                    self.processes[app.id] = nil
                    self.watchers[app.id] = nil
                    self.writeLog(session, app: app)
                }
            }
            do {
                try w.run()
                self.watchers[app.id] = w
            } catch {
                // Couldn't wait on the server; the launcher's handler will decide.
            }
        }
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
        let url = URL(fileURLWithPath: path)
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.pathExtension.lowercased() == "exe" }?.path
    }

    // MARK: - Helpers

    /// Splits a command-string into argv, honoring double quotes.
    private func tokenize(_ s: String) -> [String] {
        var out: [String] = []; var cur = ""; var inQuote = false
        for ch in s {
            if ch == "\"" { inQuote.toggle() }
            else if ch == " " && !inQuote { if !cur.isEmpty { out.append(cur); cur = "" } }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Directory of bundled CLI helpers (cabextract, 7za/7z) inside the .app.
    var bundledToolsDir: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("tools", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func baseEnv(prefix: URL, wine: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        let wineBin = (wine as NSString).deletingLastPathComponent
        var parts = [wineBin]
        if let tools = bundledToolsDir?.path { parts.append(tools) }
        parts += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = parts.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        return env
    }

    private func applyRetina(_ on: Bool, wine: String, prefix: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: wine)
        p.arguments = ["reg", "add", "HKCU\\Software\\Wine\\Mac Driver", "/v", "RetinaMode", "/d", on ? "y" : "n", "/f"]
        var env = baseEnv(prefix: prefix, wine: wine); env["WINEDEBUG"] = "-all"
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()   // fire-and-forget; the app reads it at startup
    }

    private func writeLog(_ session: LaunchSession, app: WineApp) {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let url = logsDirectory.appendingPathComponent("\(app.id).log")
        try? session.lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func logURL(for app: WineApp) -> URL? {
        let url = logsDirectory.appendingPathComponent("\(app.id).log")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Stop / force-quit

    /// Kills every process in the app's bottle (wineserver -k) and clears state.
    func forceQuit(app: WineApp, library: LibraryStore) {
        forceQuit(bottle: app.bottle, library: library)
    }

    func forceQuit(bottle: String, library: LibraryStore) {
        guard let wine = winePath else { return }
        let wineserver = (wine as NSString).deletingLastPathComponent + "/wineserver"
        guard FileManager.default.isExecutableFile(atPath: wineserver) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: wineserver)
        p.arguments = ["-k"]
        p.environment = baseEnv(prefix: prefixURL(for: bottle), wine: wine)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        for a in library.apps where a.bottle == bottle && a.running { library.setRunning(a.id, false) }
    }

    // MARK: - Bottle tools

    /// Runs a wine builtin GUI tool (winecfg / regedit / control / explorer / taskmgr / uninstaller).
    func runTool(_ tool: String, bottle: Bottle) {
        guard let wine = winePath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: wine)
        p.arguments = [tool]
        p.environment = baseEnv(prefix: prefixURL(for: bottle.id), wine: wine)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Deletes a bottle's on-disk prefix (destructive).
    func deletePrefix(bottleID: String) {
        try? FileManager.default.removeItem(at: prefixURL(for: bottleID))
    }

    func diskUsage(bottleID: String) async -> String {
        let path = prefixURL(for: bottleID).path
        guard FileManager.default.fileExists(atPath: path) else { return "—" }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
                p.arguments = ["-sk", path]
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
                do { try p.run(); p.waitUntilExit() } catch { cont.resume(returning: "—"); return }
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let kb = Int64(out.split(separator: "\t").first ?? "") ?? 0
                cont.resume(returning: WineApp.humanSize(kb * 1024))
            }
        }
    }

    func openDriveC(bottle: Bottle) {
        let c = prefixURL(for: bottle.id).appendingPathComponent("drive_c")
        if FileManager.default.fileExists(atPath: c.path) {
            NSWorkspace.shared.open(c)
        } else {
            NSWorkspace.shared.open(prefixURL(for: bottle.id))
        }
    }

    /// Initializes (or repairs) a bottle's WINEPREFIX via wineboot, honoring its arch.
    func initBottle(_ bottle: Bottle) -> ConsoleSession {
        let session = ConsoleSession(title: "Initialize \(bottle.shortLabel)", subtitle: "wineboot · \(bottle.winArch)")
        guard let wine = winePath else {
            session.phase = .error; session.append("Wine runtime not ready yet."); return session
        }
        let prefix = prefixURL(for: bottle.id)
        try? FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: wine)
        p.arguments = ["wineboot", "-u"]
        var env = baseEnv(prefix: prefix, wine: wine)
        env["WINEARCH"] = bottle.winArch
        p.environment = env
        session.append("$ WINEARCH=\(bottle.winArch) WINEPREFIX=\(prefix.path) wineboot -u")
        stream(p, into: session)
        return session
    }

    // MARK: - winetricks

    func runWinetricks(verbs: [String], bottle: Bottle) -> ConsoleSession {
        let title = verbs.isEmpty ? "winetricks" : "winetricks \(verbs.joined(separator: " "))"
        let session = ConsoleSession(title: title, subtitle: "Bottle \(bottle.shortLabel)")
        guard let wine = winePath else {
            session.phase = .error; session.append("Wine runtime not ready yet."); return session
        }
        Task { @MainActor in
            do {
                // winetricks relies on cabextract / 7z to unpack components.
                await self.ensureWinetricksDeps(into: session)

                session.append("Preparing winetricks…")
                let script = try await Winetricks.ensureInstalled()
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = [script.path, "-q"] + verbs
                var env = baseEnv(prefix: prefixURL(for: bottle.id), wine: wine)
                env["WINE"] = wine
                env["WINESERVER"] = (wine as NSString).deletingLastPathComponent + "/wineserver"
                env["WINEARCH"] = bottle.winArch
                p.environment = env
                session.append("$ winetricks -q \(verbs.joined(separator: " "))")
                let code = await self.runStreaming(p, into: session)
                let ok = code == 0
                session.append(ok ? "→ done." : "→ exited with code \(code).")
                session.phase = ok ? .exited : .error
                Notifier.notify(ok ? "Finished: \(title)" : "Failed: \(title)",
                                ok ? "Completed successfully." : "Exited with code \(code).")
            } catch {
                session.phase = .error
                session.append("error: \(error.localizedDescription)")
            }
        }
        return session
    }

    /// Ensures cabextract/7z are installed (via Homebrew) so winetricks can unpack
    /// CAB-based components. Best-effort; reports guidance if Homebrew is absent.
    /// Makes the bundled tools owner-writable and strips the download-quarantine
    /// flag so they can be exec'd (and so `xattr -dr` on the app won't choke).
    private func prepareBundledTools() {
        guard let dir = bundledToolsDir?.path else { return }
        for t in ["cabextract", "7za"] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(dir)/\(t)")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-dr", "com.apple.quarantine", dir]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private func ensureWinetricksDeps(into session: ConsoleSession) async {
        prepareBundledTools()
        let missing = ["cabextract", "7z"].filter { !hasTool($0) }
        guard !missing.isEmpty else { return }
        session.append("winetricks needs: \(missing.joined(separator: ", ")).")
        guard let brew = brewPath() else {
            session.append("Homebrew was not found — install it, then the components:")
            session.append("  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
            session.append("  brew install cabextract p7zip")
            return
        }
        session.append("Installing cabextract + p7zip via Homebrew (one-time)…")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: brew)
        p.arguments = ["install", "cabextract", "p7zip"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\((brew as NSString).deletingLastPathComponent):/usr/bin:/bin:" + (env["PATH"] ?? "")
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        env["NONINTERACTIVE"] = "1"
        p.environment = env
        _ = await runStreaming(p, into: session)
    }

    private func hasTool(_ name: String) -> Bool {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        if let t = bundledToolsDir?.path { dirs.insert(t, at: 0) }
        return dirs.contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(name)") }
    }
    private func brewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs a process, streaming merged stdout/stderr into the session, and
    /// resumes with its exit code when it finishes.
    private func runStreaming(_ proc: Process, into session: ConsoleSession) async -> Int32 {
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in session.ingest(text) }
        }
        return await withCheckedContinuation { cont in
            proc.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: p.terminationStatus)
            }
            do { try proc.run() } catch {
                let msg = error.localizedDescription
                Task { @MainActor in session.append("error: \(msg)") }
                cont.resume(returning: -1)
            }
        }
    }

    /// Sets the bottle's reported Windows version via winetricks (win7/win10/win11).
    func setWindowsVersion(_ bottle: Bottle) -> ConsoleSession {
        runWinetricks(verbs: [bottle.winVersion], bottle: bottle)
    }

    /// Runs a Windows installer (.exe or .msi) inside the given bottle, streaming
    /// the wine output to a ConsoleSession. The installer's own GUI handles the
    /// next/finish clicks; we just keep wine alive and surface its logs.
    func runInstaller(at url: URL, bottle: Bottle) -> ConsoleSession {
        let title = "Install \(url.lastPathComponent)"
        let session = ConsoleSession(title: title, subtitle: "Bottle \(bottle.shortLabel)")
        guard let wine = winePath else {
            session.phase = .error; session.append("Wine runtime not ready yet."); return session
        }
        let prefix = prefixURL(for: bottle.id)
        try? FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let path = url.path
        let isMSI = path.lowercased().hasSuffix(".msi")

        Task { @MainActor in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: wine)
            p.arguments = isMSI ? ["msiexec", "/i", path] : [path]
            p.environment = baseEnv(prefix: prefix, wine: wine)
            p.currentDirectoryURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)
            session.append("$ WINEPREFIX=\(prefix.path) \\")
            session.append("  wine \(isMSI ? "msiexec /i " : "")\"\(path)\"")
            let code = await self.runStreaming(p, into: session)
            let ok = code == 0
            session.append(ok ? "→ installer finished. Use \"Scan for Apps\" to add it to your library."
                              : "→ installer exited with code \(code).")
            session.phase = ok ? .exited : .error
            Notifier.notify(ok ? "Installed: \(url.lastPathComponent)" : "Installer failed",
                            ok ? "Open the bottle and use Scan for Apps to register it." : "Exited with code \(code).")
        }
        return session
    }

    /// Streams a process's merged stdout/stderr into a ConsoleSession.
    private func stream(_ proc: Process, into session: ConsoleSession) {
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in session.ingest(text) }
        }
        let taskTitle = session.title
        proc.terminationHandler = { p in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                session.flush()
                let ok = p.terminationStatus == 0
                session.append(ok ? "→ done." : "→ exited with code \(p.terminationStatus).")
                session.phase = ok ? .exited : .error
                Notifier.notify(ok ? "Finished: \(taskTitle)" : "Failed: \(taskTitle)",
                                ok ? "Completed successfully." : "Exited with code \(p.terminationStatus).")
            }
        }
        do { try proc.run() } catch {
            session.phase = .error
            session.append("error: \(error.localizedDescription)")
        }
    }
}
