import Foundation

/// Downloads the latest "native" DXMT release from Sikarugir-App/dxmt and copies
/// its `d3d11.dll` / `dxgi.dll` into a bottle's system32 / syswow64.
enum DXMTInstaller {
    private static let api = URL(string:
        "https://api.github.com/repos/Sikarugir-App/dxmt/releases?per_page=3")!

    /// Returns the installed version on success.
    static func install(into prefix: URL) async throws -> String {
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MacTuak", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        let releases = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []

        var found: (tag: String, url: URL)?
        outer: for rel in releases {
            let tag = rel["tag_name"] as? String ?? ""
            for a in (rel["assets"] as? [[String: Any]]) ?? [] {
                guard let name = a["name"] as? String,
                      name.hasSuffix("-native.tar.gz"),
                      let urlStr = a["browser_download_url"] as? String,
                      let url = URL(string: urlStr) else { continue }
                found = (tag, url); break outer
            }
        }
        guard let (version, url) = found else {
            throw NSError(domain: "MacTuak", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "No DXMT native asset on Sikarugir-App/dxmt."])
        }

        let (tmp, _) = try await URLSession.shared.download(from: url)
        let archive = FileManager.default.temporaryDirectory
            .appendingPathComponent("dxmt-\(UUID().uuidString).tar.gz")
        try? FileManager.default.removeItem(at: archive)
        try FileManager.default.moveItem(at: tmp, to: archive)

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("dxmt-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        extract.arguments = ["-xzf", archive.path, "-C", staging.path]
        try extract.run(); extract.waitUntilExit()
        if extract.terminationStatus != 0 {
            throw NSError(domain: "MacTuak", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "tar failed extracting DXMT"])
        }

        try installDLLs(from: staging, into: prefix)

        try? FileManager.default.removeItem(at: archive)
        try? FileManager.default.removeItem(at: staging)
        return version
    }

    /// Walk the staging tree and copy DLLs into the bottle's system32 /
    /// syswow64 according to the source folder (`x64` vs `x32`/`x86`).
    private static func installDLLs(from staging: URL, into prefix: URL) throws {
        let fm = FileManager.default
        let sys32   = prefix.appendingPathComponent("drive_c/windows/system32",  isDirectory: true)
        let sysWow  = prefix.appendingPathComponent("drive_c/windows/syswow64",  isDirectory: true)
        try? fm.createDirectory(at: sys32,  withIntermediateDirectories: true)
        try? fm.createDirectory(at: sysWow, withIntermediateDirectories: true)

        guard let en = fm.enumerator(at: staging, includingPropertiesForKeys: nil) else { return }
        for case let f as URL in en {
            guard f.pathExtension.lowercased() == "dll" else { continue }
            let parent = f.deletingLastPathComponent().lastPathComponent.lowercased()
            let dest: URL
            switch parent {
            case "x64":         dest = sys32.appendingPathComponent(f.lastPathComponent)
            case "x32", "x86":  dest = sysWow.appendingPathComponent(f.lastPathComponent)
            default: continue
            }
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: f, to: dest)
        }
    }
}
