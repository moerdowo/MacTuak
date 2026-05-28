import Foundation
import AppKit

/// Generates a standalone double-clickable .app in ~/Applications that launches a
/// library app through the managed Wine runtime — independent of MacTuak.
enum AppExporter {
    @discardableResult
    static func export(app: WineApp, winePath: String, prefix: URL) throws -> URL {
        let fm = FileManager.default
        let appsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        try? fm.createDirectory(at: appsDir, withIntermediateDirectories: true)

        let safe = app.name.replacingOccurrences(of: "/", with: "-")
        let appURL = appsDir.appendingPathComponent("\(safe).app")
        try? fm.removeItem(at: appURL)
        let macos = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let res = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.createDirectory(at: res, withIntermediateDirectories: true)

        // Launcher script — resolves the current Wine binary at run time so it
        // survives Wine auto-updates (paths include the version).
        let exec = macos.appendingPathComponent(safe)
        let args = app.opts.arguments
        let script = """
        #!/bin/bash
        INFO="$HOME/Library/Application Support/MacTuak/Wine/installed.json"
        WINE=$(/usr/bin/python3 -c "import json;print(json.load(open('$INFO'))['binary'])" 2>/dev/null)
        [ -z "$WINE" ] && WINE="\(winePath)"
        export WINEPREFIX="\(prefix.path)"
        export WINEESYNC=\(app.opts.esync ? "1" : "0")
        export PATH="$(dirname "$WINE"):/usr/bin:/bin:$PATH"
        exec "$WINE" "\(app.exePath)" \(args)
        """
        try script.write(to: exec, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)

        // Info.plist
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleName</key><string>\(safe)</string>
          <key>CFBundleDisplayName</key><string>\(app.name)</string>
          <key>CFBundleIdentifier</key><string>com.mactuak.launcher.\(app.id)</string>
          <key>CFBundleVersion</key><string>1.0</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleExecutable</key><string>\(safe)</string>
          <key>CFBundleIconFile</key><string>AppIcon</string>
          <key>NSHighResolutionCapable</key><true/>
        </dict></plist>
        """
        try plist.write(to: appURL.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)

        // Icon: convert the app's custom/extracted icon to .icns, else reuse MacTuak's.
        let icnsDest = res.appendingPathComponent("AppIcon.icns")
        if let png = app.iconURL, fm.fileExists(atPath: png.path), sipsToICNS(png.path, icnsDest.path) {
            // done
        } else if let bundled = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            try? fm.copyItem(at: bundled, to: icnsDest)
        }

        // Touch so Finder refreshes the icon.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: appURL.path)
        return appURL
    }

    private static func sipsToICNS(_ src: String, _ dst: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        p.arguments = ["-s", "format", "icns", src, "--out", dst]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }
}
