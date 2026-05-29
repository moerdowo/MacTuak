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
                message: "MacTuak bundles cabextract; this build seems to be missing it. Reinstall the latest DMG, or as a fallback run `brew install cabextract`.")
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

        // DXVK 2.x can't initialize on MoltenVK (no geometry shader on Apple GPUs).
        if l.contains("dxvk: no adapters found") ||
           l.contains("'geometryshader'") ||
           l.contains("dxvk::dxvkerror") {
            return Hint(key: "dxvk-no-adapter",
                message: "DXVK 2.x needs Vulkan features that MoltenVK on Apple Silicon doesn't expose (geometry shaders). For Electron/Chromium apps, the right fix is to skip GPU accel entirely: add --disable-gpu in Edit Info → Launch Options. For other apps, try the older DXVK (`winetricks dxvk1103`) or use a Wine build with Apple GPTK patches (Whisky/CrossOver).")
        }

        // Direct3D failing on wined3d (OpenGL) on macOS — install DXVK.
        if l.contains("requested d3d feature levels") ||
           l.contains("gl_invalid_framebuffer_operation") ||
           (l.contains("wined3d_select_feature_level") && l.contains("none")) ||
           l.contains("gl_surface_egl") ||
           l.contains("eglinitialize") {
            return Hint(key: "needs-dxvk",
                message: "Wine's built-in wined3d can't do modern Direct3D on macOS. Install dxvk from the Winetricks Browser to route D3D9/10/11 through Vulkan → MoltenVK → Metal. If this is a Chromium/Electron app, also add --disable-gpu in Edit Info → Launch Options → Arguments.")
        }

        // libgnutls missing — wine prints this when it can't find the macOS
        // libgnutls dylib to back its Windows TLS providers. Apps still run,
        // but in-app HTTPS / login servers won't work. Known limitation.
        if l.contains("failed to load libgnutls") {
            return Hint(key: "no-gnutls",
                message: "HTTPS inside Windows apps won't work — MacTuak doesn't yet ship a universal libgnutls (the chain is heavy and x86_64-on-Apple-Silicon builds keep failing in our pipeline). The game itself usually runs fine; only network/TLS features inside it are affected.")
        }

        // esync mismatch — wineserver wasn't started with esync but the
        // launching wine wants it. Common after engine swaps.
        if l.contains("err:esync") || l.contains("wineserver instances are running without wineesync") {
            return Hint(key: "esync-stale",
                message: "Esync clashed with the existing wineserver. In Edit Info → Launch Options, turn off Esync; or use Bottle Manager → Force Quit on the bottle, then relaunch.")
        }

        // Wine builtin D3D11/DXGI not loadable — usually the prefix was created
        // under a different wine engine. Initialize/Repair the bottle, or
        // install real DLLs via DXMT/DXVK.
        if l.contains("err:module:import_dll") &&
           (l.contains("dxgi.dll") || l.contains("d3d11.dll") || l.contains("d3d10.dll") || l.contains("d3d9.dll")) {
            return Hint(key: "missing-d3d-builtin",
                message: "Wine builtin DXGI/D3D didn't load — usually because the prefix was set up under a different engine. Try Bottle Manager → Initialize / Repair on this bottle. If that doesn't fix it, enable DXMT (or DXVK) in the bottle's Direct3D Backend section.")
        }

        // App needs a DLL that isn't installed.
        if (l.contains("err:module:import_dll") && l.contains("not found")) ||
           (l.contains("err:module:") && (l.contains("module not found") || l.contains("loadlibrary"))) {
            return Hint(key: "missing-dll",
                message: "A Windows DLL is missing. Try Bottle Manager → Initialize / Repair first (re-seeds wine builtins). If still missing, install vcrun2019 / dotnet48 / d3dcompiler_47 via the Winetricks Browser.")
        }

        return nil
    }
}
