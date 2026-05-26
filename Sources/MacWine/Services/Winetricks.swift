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
}
