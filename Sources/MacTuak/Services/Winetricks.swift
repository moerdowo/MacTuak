import Foundation

/// Downloads and caches the winetricks script so bottles can install common
/// runtime components (DXVK, VC++ runtimes, .NET, fonts, Windows version, …).
enum Winetricks {
    static var scriptURL: URL {
        LibraryStore.supportDirectory.appendingPathComponent("winetricks", isDirectory: false)
    }
    private static let remote = URL(string:
        "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks")!

    /// Returns the local winetricks path, downloading it if missing.
    static func ensureInstalled() async throws -> URL {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: scriptURL.path) { return scriptURL }
        let (data, _) = try await URLSession.shared.data(from: remote)
        try? fm.createDirectory(at: LibraryStore.supportDirectory, withIntermediateDirectories: true)
        try data.write(to: scriptURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    /// Auto-installed when "Install common runtimes" is enabled on a new bottle.
    /// Covers the dependencies most Windows apps assume: Microsoft TrueType
    /// fonts (corefonts), CJK fallback fonts (so Japanese / Chinese / Korean
    /// games don't render blank), VC++ 2015–2019, the Direct3D shader
    /// compiler, GDI+, and XACT audio.
    static let coreRuntimeVerbs = ["corefonts", "cjkfonts", "vcrun2019", "d3dcompiler_47", "gdiplus", "xact"]

    /// Curated verbs offered in the bottle UI.
    static let commonVerbs: [(verb: String, label: String)] = [
        ("dxvk", "DXVK (Direct3D→Vulkan)"),
        ("vkd3d", "VKD3D (Direct3D 12)"),
        ("corefonts", "Core fonts"),
        ("vcrun2019", "Visual C++ 2015–2019"),
        ("vcrun2022", "Visual C++ 2022"),
        ("dotnet48", ".NET Framework 4.8"),
        ("d3dx9", "DirectX 9 (d3dx9)"),
        ("d3dcompiler_47", "d3dcompiler_47"),
        ("gdiplus", "GDI+"),
        ("xact", "XACT audio"),
    ]

    /// Categories winetricks groups verbs under.
    static let categories: [(name: String, label: String, system: String)] = [
        ("dlls",       "DLLs",       "puzzlepiece.extension"),
        ("fonts",      "Fonts",      "textformat"),
        ("apps",       "Apps",       "app.fill"),
        ("settings",   "Settings",   "gearshape"),
        ("games",      "Games",      "gamecontroller"),
        ("benchmarks", "Benchmarks", "speedometer"),
        ("prefix",     "Prefix",     "wineglass"),
    ]
}

struct WinetricksVerb: Hashable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
}

struct WinetricksCategory: Identifiable {
    var id: String { name }
    let name: String
    let label: String
    let system: String
    let verbs: [WinetricksVerb]
}

extension Winetricks {
    /// Runs `winetricks <category> list` and parses verb/description rows.
    nonisolated static func listVerbs(category: String, scriptPath: URL,
                                      wine: String, prefix: URL, arch: String,
                                      toolsPath: String?) -> [WinetricksVerb] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [scriptPath.path, category, "list"]
        var env = ProcessInfo.processInfo.environment
        env["WINE"] = wine
        env["WINESERVER"] = (wine as NSString).deletingLastPathComponent + "/wineserver"
        env["WINEPREFIX"] = prefix.path
        env["WINEARCH"] = arch
        let wineBin = (wine as NSString).deletingLastPathComponent
        var pathParts = [wineBin]
        if let toolsPath { pathParts.append(toolsPath) }
        pathParts += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        env["PATH"] = pathParts.joined(separator: ":")
        proc.environment = env

        let out = Pipe(); proc.standardOutput = out; proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return parse(text)
    }

    nonisolated private static func parse(_ text: String) -> [WinetricksVerb] {
        var verbs: [WinetricksVerb] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("="), !line.hasPrefix("-"),
                  !line.lowercased().hasPrefix("warning"),
                  !line.lowercased().hasPrefix("using winetricks"),
                  !line.lowercased().hasPrefix("usage:") else { continue }
            guard let split = line.firstIndex(where: { $0.isWhitespace }) else { continue }
            let name = String(line[..<split])
            // Verb names are short tokens (letters, digits, _ - +); skip anything else.
            let allowed = CharacterSet(charactersIn:
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-+")
            guard !name.isEmpty,
                  name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { continue }
            let desc = line[split...].trimmingCharacters(in: .whitespaces)
            verbs.append(WinetricksVerb(name: name, description: desc))
        }
        return verbs
    }
}
