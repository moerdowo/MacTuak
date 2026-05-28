import Foundation

/// Watches wine/winetricks output for common failure signatures and returns a
/// short, actionable suggestion. Sessions de-dupe by `key` so a given hint
/// is posted at most once per run.
enum WineHints {
    struct Hint: Equatable { let key: String; let message: String }

    static func match(_ line: String) -> Hint? {
        let l = line.lowercased()

        // Old InstallShield / RPG Maker style stack overflow on wow64 Wine.
        if l.contains("err:virtual") && l.contains("stack overflow") {
            return Hint(key: "stack-overflow",
                message: "Old installers often crash with stack overflow on wow64 Wine. Try: set the bottle's Windows version to 7 (Bottle Manager → Apply), install vcrun6 + corefonts + vbrun60sp6 from the Winetricks Browser, then retry. If it still fails, prefer a portable build/folder over the installer.")
        }

        // We bundle cabextract; if a copy is missing, the user has a stale install.
        if l.contains("cannot find cabextract") {
            return Hint(key: "cabextract-missing",
                message: "MacWine bundles cabextract; this build seems to be missing it. Reinstall the latest DMG, or as a fallback run `brew install cabextract`.")
        }

        // Generic access-violation / segfault — most often a missing runtime.
        if l.contains("0xc0000005") || (l.contains("err:seh") && l.contains("guard page")) {
            return Hint(key: "access-violation",
                message: "Access violation — usually a missing runtime. Try installing vcrun2019 + d3dcompiler_47 from the Winetricks Browser, or change the bottle's Windows version (Bottle Manager → Apply).")
        }

        // wow64 mode rejecting WINEARCH=win32.
        if l.contains("winearch") && l.contains("not supported in wow64") {
            return Hint(key: "wow64-arch",
                message: "The bundled Wine is wow64 — only 64-bit prefixes. 32-bit Windows apps still run inside one via WoW64; delete this bottle and create a new one (it'll be 64-bit automatically).")
        }

        // App needs a DLL that isn't installed.
        if l.contains("err:module:") && (l.contains("module not found") || l.contains("loadlibrary")) {
            return Hint(key: "missing-dll",
                message: "A Windows DLL is missing. The most common fixes are installing vcrun2019, dotnet48, or d3dcompiler_47 via the Winetricks Browser.")
        }

        return nil
    }
}
