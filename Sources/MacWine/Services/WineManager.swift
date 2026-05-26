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

    init() { bootstrap() }

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

        Task.detached(priority: .utility) {
            do {
                let release = try await WineInstaller.latestStable()

                // Already on the latest managed build?
                if let info = currentInfo, info.version == release.version,
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
                Self.saveInfo(InstalledInfo(version: release.version, binary: bin))
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
        let target = resolveExecutable(app.exePath)

        session.append("$ \(wine) --version")
        session.append("Wine \(activeVersion)")
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
        let url = URL(fileURLWithPath: path)
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.pathExtension.lowercased() == "exe" }?.path
    }
}
