import Foundation
import Combine
import AppKit

/// The persisted app library + bottles. Source of truth for the grid/list.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var apps: [WineApp] = []
    @Published var bottles: [Bottle] = []

    private let fileURL: URL

    private struct Payload: Codable {
        var apps: [WineApp]
        var bottles: [Bottle]
    }

    init() {
        let dir = LibraryStore.supportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("library.json")
        load()
    }

    nonisolated static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let newDir = base.appendingPathComponent("MacTuak", isDirectory: true)
        // One-time migration: app was renamed from "MacWine" → "MacTuak".
        // If the old support folder exists and the new one doesn't, move it over
        // so bottles / library / Wine runtime / icons / logs survive the rename.
        let oldDir = base.appendingPathComponent("MacWine", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: oldDir.path) && !fm.fileExists(atPath: newDir.path) {
            try? fm.moveItem(at: oldDir, to: newDir)
        }
        return newDir
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            bottles = Bottle.defaults
            apps = []
            return
        }
        // Rewrite any exePaths that pointed inside the old MacWine support
        // folder so apps installed via Scan-for-Apps survive the rename.
        var changed = false
        apps = payload.apps.map { a in
            guard a.exePath.contains("/Application Support/MacWine/") else { return a }
            var u = a
            u.exePath = a.exePath.replacingOccurrences(of: "/Application Support/MacWine/",
                                                       with: "/Application Support/MacTuak/")
            changed = true
            return u
        }
        bottles = payload.bottles.isEmpty ? Bottle.defaults : payload.bottles
        if changed { save() }
    }

    private func save() {
        let payload = Payload(apps: apps, bottles: bottles)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Mutations

    func add(_ app: WineApp) {
        apps.insert(app, at: 0)
        save()
    }

    @discardableResult
    func importFile(at url: URL, bottle: String) -> WineApp {
        var app = WineApp.imported(from: url, bottle: bottle)
        autoDetect(&app)
        add(app)
        return app
    }

    /// Reads the .exe's PE header to set arch and (if no custom icon yet) extract
    /// the embedded icon.
    func autoDetect(_ app: inout WineApp) {
        guard app.exePath.lowercased().hasSuffix(".exe") else { return }
        if let arch = PEInfo.architecture(of: app.exePath) { app.arch = arch }
        if app.iconFileName == nil, let img = PEInfo.icon(of: app.exePath),
           let name = writeIcon(img, appID: app.id) {
            app.iconFileName = name
        }
    }

    func remove(_ app: WineApp) {
        apps.removeAll { $0.id == app.id }
        save()
    }

    func toggleFavorite(_ app: WineApp) {
        guard let i = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[i].favorite.toggle()
        save()
    }

    func setCategory(_ app: WineApp, _ category: String) {
        guard let i = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[i].category = category
        save()
    }

    /// Replaces an app in place (used by the Edit Info sheet) and persists.
    func update(_ updated: WineApp) {
        guard let i = apps.firstIndex(where: { $0.id == updated.id }) else { return }
        var u = updated
        u.running = apps[i].running   // preserve transient live state
        apps[i] = u
        save()
    }

    // MARK: - Custom icons

    /// Writes an image into the Icons dir under a fresh filename and returns it.
    func writeIcon(_ image: NSImage, appID: String) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let dir = WineApp.iconsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(appID)-\(UUID().uuidString.prefix(8)).png"
        do { try png.write(to: dir.appendingPathComponent(name), options: .atomic) } catch { return nil }
        return name
    }

    func deleteIcon(named name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: WineApp.iconsDirectory.appendingPathComponent(name))
    }

    func setRunning(_ id: String, _ running: Bool) {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[i].running = running
        if running { apps[i].lastRun = Date() }
        save()
    }

    func ensureBottle(_ id: String, label: String? = nil, wineVersion: String = "9.0") {
        guard !bottles.contains(where: { $0.id == id }) else { return }
        bottles.append(Bottle(id: id, label: label ?? id, wineVersion: wineVersion))
        save()
    }

    @discardableResult
    func addBottle(label: String, windowsVersion: String, arch: String) -> Bottle {
        let base = label.lowercased().replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        var id = base.isEmpty ? "bottle" : base
        var n = 1
        while bottles.contains(where: { $0.id == id }) { n += 1; id = "\(base)-\(n)" }
        let b = Bottle(id: id, label: label, wineVersion: "9.0", windowsVersion: windowsVersion, arch: arch)
        bottles.append(b)
        save()
        return b
    }

    func updateBottle(_ bottle: Bottle) {
        guard let i = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[i] = bottle
        save()
    }

    func renameBottle(_ id: String, to label: String) {
        guard let i = bottles.firstIndex(where: { $0.id == id }) else { return }
        bottles[i].label = label
        save()
    }

    /// Removes a bottle entry. Apps assigned to it are reassigned to the first
    /// remaining bottle. (The on-disk prefix is deleted separately by WineManager.)
    func deleteBottle(_ id: String) {
        bottles.removeAll { $0.id == id }
        let fallback = bottles.first?.id ?? "win10-x64"
        for i in apps.indices where apps[i].bottle == id { apps[i].bottle = fallback }
        save()
    }

    // MARK: - Derived

    var counts: [String: Int] {
        var c: [String: Int] = ["All": apps.count, "Favorites": 0, "Running": 0]
        for cat in Theme.categories where cat != "All" { c[cat] = 0 }
        for a in apps {
            c[a.category, default: 0] += 1
            if a.favorite { c["Favorites", default: 0] += 1 }
            if a.running { c["Running", default: 0] += 1 }
        }
        return c
    }

    func bottleAppCount(_ id: String) -> Int { apps.filter { $0.bottle == id }.count }
    var runningCount: Int { apps.filter { $0.running }.count }
}
