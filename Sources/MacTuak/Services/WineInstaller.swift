import Foundation

/// Fetches, downloads, and extracts portable stable Wine builds from the
/// Gcenx/macOS_Wine_builds GitHub releases. All members are nonisolated so they
/// run off the main actor.
enum WineInstaller {
    struct Release: Sendable {
        let version: String       // release tag, e.g. "11.0_1"
        let assetName: String
        let url: URL
    }

    private static let releasesAPI = URL(string:
        "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases?per_page=50")!

    /// Newest release that ships a `wine-<channel>-*-osx64.tar.xz` asset.
    /// channel ∈ {stable, staging, devel}.
    static func latest(channel: String) async throws -> Release {
        var req = URLRequest(url: releasesAPI)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MacTuak", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        let releases = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let key = "wine-\(channel.lowercased())"
        for rel in releases {
            let tag = rel["tag_name"] as? String ?? ""
            let assets = rel["assets"] as? [[String: Any]] ?? []
            if let asset = assets.first(where: {
                let n = ($0["name"] as? String ?? "").lowercased()
                return n.hasPrefix(key) && n.hasSuffix(".tar.xz")
            }), let s = asset["browser_download_url"] as? String, let url = URL(string: s) {
                return Release(version: tag, assetName: asset["name"] as? String ?? "", url: url)
            }
        }
        throw err("No \(channel) Wine build found in releases.")
    }

    /// Downloads `url` to a temp file, reporting 0…1 progress.
    static func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await Downloader(progress: progress).run(url: url)
    }

    /// Extracts a `.tar.xz` into `dir` (cleared first) using bsdtar.
    static func extract(_ archive: URL, into dir: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["-xf", archive.path, "-C", dir.path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        proc.environment = env
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw err("Extraction failed: \(msg)")
        }
    }

    /// Finds the wine binary inside an extracted tree (prefers wine64).
    static func findWineBinary(in dir: URL) -> String? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        var wine64: String?
        var wine: String?
        for case let f as URL in en {
            let p = f.path
            if p.hasSuffix("/wine/bin/wine64") { wine64 = p }
            else if p.hasSuffix("/wine/bin/wine") { wine = p }
        }
        return wine64 ?? wine
    }

    private static func err(_ m: String) -> NSError {
        NSError(domain: "MacTuak", code: 1, userInfo: [NSLocalizedDescriptionKey: m])
    }
}

/// URLSession download with progress, bridged to async/await.
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private var cont: CheckedContinuation<URL, Error>?

    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func run(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            self.cont = c
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForResource = 1800
            let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is removed once this returns, so move it somewhere stable now.
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactuak-\(UUID().uuidString).tar.xz")
        do {
            try FileManager.default.moveItem(at: location, to: dst)
            cont?.resume(returning: dst)
        } catch {
            cont?.resume(throwing: error)
        }
        cont = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { cont?.resume(throwing: error); cont = nil }
    }
}
