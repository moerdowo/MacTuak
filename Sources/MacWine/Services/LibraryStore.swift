import Foundation
import Combine

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

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MacWine", isDirectory: true)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            bottles = Bottle.defaults
            apps = []
            return
        }
        apps = payload.apps
        bottles = payload.bottles.isEmpty ? Bottle.defaults : payload.bottles
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
        let app = WineApp.imported(from: url, bottle: bottle)
        add(app)
        return app
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
