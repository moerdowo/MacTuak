import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var wine: WineManager

    @State private var section = "library:All"
    @State private var query = ""
    @State private var launch: LaunchSession?
    @State private var adding = false
    @State private var editing: WineApp?
    @State private var showBottles = false
    @State private var prefilledURL: URL?
    @State private var recentlyUninstalled: WineApp?
    @State private var undoTask: Task<Void, Never>?
    @State private var draggingFile = false
    @State private var onboardingDismissed = false

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 12)]

    var body: some View {
        let accent = settings.accentColor
        let p = Palette.make(settings.dark)
        ZStack {
            p.appBG.ignoresSafeArea()

            HStack(spacing: 0) {
                Sidebar(section: $section, onAdd: openAdd, onManageBottles: { showBottles = true })
                mainColumn(accent: accent)
            }

            if let recentlyUninstalled {
                VStack { Spacer()
                    UninstallToast(app: recentlyUninstalled, accent: accent) { undoUninstall() }
                        .padding(.bottom, 52)
                }
            }
            if draggingFile { DropOverlay(accent: accent) }
            if let launch {
                LaunchOverlay(session: launch, accent: accent) { self.launch = nil }
                    .zIndex(50)
            }
            if adding {
                AddAppSheet(accent: accent, prefilled: prefilledURL,
                            onClose: { adding = false; prefilledURL = nil },
                            onAdded: { _ in })
                    .zIndex(60)
            }
            if let editing {
                EditAppSheet(app: editing, accent: accent, onClose: { self.editing = nil })
                    .zIndex(60)
            }
            if showBottles {
                BottleManagerSheet(accent: accent, onClose: { showBottles = false })
                    .zIndex(70)
            }
            if showOnboarding {
                OnboardingOverlay(accent: accent, onContinue: { onboardingDismissed = true })
                    .zIndex(80)
            }
        }
        .onAppear { wine.channel = settings.wineChannel }
        .environment(\.palette, p)
        .preferredColorScheme(settings.dark ? .dark : .light)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: launch != nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: adding)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: editing != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: recentlyUninstalled)
        .onDrop(of: [.fileURL], isTargeted: $draggingFile) { providers in handleWindowDrop(providers) }
        .ignoresSafeArea()
    }

    // MARK: - Main column

    private func mainColumn(accent: Color) -> some View {
        let list = visibleApps
        let p = Palette.make(settings.dark)
        return VStack(spacing: 0) {
            MainToolbar(title: sectionTitle,
                        subtitle: "\(list.count) app\(list.count == 1 ? "" : "s")",
                        query: $query, onAdd: openAdd)

            ScrollView {
                if list.isEmpty {
                    EmptyStateView(accent: accent, hasQuery: !query.trimmed.isEmpty, onAdd: openAdd)
                } else if settings.view == "grid" {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(list) { app in
                            AppTile(app: app, accent: accent,
                                    onLaunch: { runApp(app) },
                                    onToggleFav: { library.toggleFavorite(app) },
                                    menu: { AnyView(menu(for: app)) })
                        }
                    }
                    .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 28)
                } else {
                    VStack(spacing: 0) {
                        ListHeaderRow()
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, app in
                            AppListRow(app: app, accent: accent, isLast: i == list.count - 1,
                                       onLaunch: { runApp(app) },
                                       menu: { AnyView(menu(for: app)) })
                        }
                    }
                    .background(p.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
                    .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 28)
                }
            }

            StatusBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.contentBG)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func menu(for app: WineApp) -> some View {
        Button { runApp(app) } label: { Label("Run", systemImage: "play.fill") }
        Button { runApp(app, admin: true) } label: { Label("Run as administrator", systemImage: "sparkles") }
        if app.running {
            Button(role: .destructive) { wine.forceQuit(app: app, library: library) } label: {
                Label("Force Quit (bottle)", systemImage: "stop.fill")
            }
        }
        Divider()
        Button { editing = app } label: { Label("Edit Info…", systemImage: "info.circle") }
        Button { exportApp(app) } label: { Label("Add to Applications", systemImage: "square.and.arrow.down.on.square") }
        Button { library.toggleFavorite(app) } label: {
            Label(app.favorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: app.favorite ? "star.slash" : "star")
        }
        Menu {
            ForEach(Theme.categories.filter { $0 != "All" }, id: \.self) { cat in
                Button { library.setCategory(app, cat) } label: {
                    if app.category == cat { Label(cat, systemImage: "checkmark") } else { Text(cat) }
                }
            }
        } label: { Label("Category", systemImage: "tag") }
        Button { showInFinder(app) } label: { Label("Show in Finder", systemImage: "folder") }
        Button { section = "bottle:\(app.bottle)" } label: { Label("Configure Wine bottle…", systemImage: "wineglass") }
        Divider()
        Button(role: .destructive) { uninstall(app) } label: { Label("Uninstall", systemImage: "trash") }
    }

    // MARK: - Derived

    private var visibleApps: [WineApp] {
        var list = library.apps
        let parts = section.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "library"
        let val = parts.count > 1 ? parts[1] : "All"
        if kind == "library" {
            switch val {
            case "All": break
            case "Favorites": list = list.filter { $0.favorite }
            case "Running": list = list.filter { $0.running }
            case "Recent": list = list.sorted { $0.recencyScore < $1.recencyScore }.prefix(8).map { $0 }
            default: list = list.filter { $0.category == val }
            }
        } else if kind == "bottle" {
            list = list.filter { $0.bottle == val }
        }
        let q = query.trimmed.lowercased()
        if !q.isEmpty {
            list = list.filter { ($0.name + $0.publisher + $0.category).lowercased().contains(q) }
        }
        if !(kind == "library" && val == "Recent") {
            switch settings.sort {
            case "recent": list.sort { $0.recencyScore < $1.recencyScore }
            case "size":   list.sort { $0.sizeBytes > $1.sizeBytes }
            case "added":  list.sort { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            default:       list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
        return list
    }

    private var sectionTitle: String {
        let parts = section.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "library"
        let val = parts.count > 1 ? parts[1] : "All"
        if kind == "library" { return val == "All" ? "All Apps" : val }
        if kind == "bottle" { return library.bottles.first { $0.id == val }?.label ?? "Bottle" }
        return "Library"
    }

    // MARK: - Actions

    private func openAdd() { adding = true }

    private var showOnboarding: Bool {
        !onboardingDismissed && library.apps.isEmpty &&
        [.detecting, .needsDownload, .downloading, .extracting, .installing].contains(wine.runtime.kind)
    }

    private func runApp(_ app: WineApp, admin: Bool = false) {
        launch = wine.launch(app: app, admin: admin, library: library)
    }

    private func exportApp(_ app: WineApp) {
        guard let winePath = wine.winePath else { return }
        let prefix = wine.prefixURL(for: app.bottle)
        Task.detached {
            guard let url = try? AppExporter.export(app: app, winePath: winePath, prefix: prefix) else { return }
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                Notifier.notify("Added to Applications", "\(app.name) launcher created in ~/Applications.")
            }
        }
    }

    private func uninstall(_ app: WineApp) {
        undoTask?.cancel()
        library.remove(app)
        recentlyUninstalled = app
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { recentlyUninstalled = nil }
        }
    }

    private func undoUninstall() {
        guard let app = recentlyUninstalled else { return }
        undoTask?.cancel()
        library.add(app)
        recentlyUninstalled = nil
    }

    private func showInFinder(_ app: WineApp) {
        let url = URL(fileURLWithPath: app.exePath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func handleWindowDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                prefilledURL = url
                adding = true
            }
        }
        return true
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
