import SwiftUI

/// A polished, app-store-style browser over the winetricks `apps` catalog.
/// Install with one click; new programs are auto-imported into the library.
struct WinetricksAppStoreSheet: View {
    @EnvironmentObject var wine: WineManager
    @EnvironmentObject var library: LibraryStore
    @Environment(\.palette) private var p
    let accent: Color
    var onConsole: (ConsoleSession) -> Void
    var onClose: () -> Void

    @State private var bottleID: String = ""
    @State private var query: String = ""
    @State private var installing: Set<String> = []

    private var bottle: Bottle? { library.bottles.first { $0.id == bottleID } }
    private var apps: [WinetricksVerb] {
        wine.winetricksCatalog.first { $0.name == "apps" }?.verbs ?? []
    }
    private var filtered: [WinetricksVerb] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return apps }
        return apps.filter { $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }
    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)]

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                if wine.catalogLoading && apps.isEmpty {
                    loadingState
                } else if apps.isEmpty {
                    failedState
                } else if filtered.isEmpty {
                    VStack { Spacer(); Text("No matches.").foregroundStyle(p.textSecondary); Spacer() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(filtered) { v in
                                AppStoreCard(verb: v, accent: accent,
                                             busy: installing.contains(v.name),
                                             alreadyInstalled: existing(for: v)) {
                                    install(v)
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .frame(width: 780, height: 560)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 40, y: 24)
        }
        .onAppear {
            if bottleID.isEmpty { bottleID = library.bottles.first?.id ?? "" }
            if let b = bottle { wine.loadWinetricksCatalog(for: b) }
        }
    }

    // MARK: - sections

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [accent, accent.darkened(0.3)], startPoint: .top, endPoint: .bottom))
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: "bag.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text("Winetricks App Store").font(.system(size: 16, weight: .bold)).foregroundStyle(p.text)
                Text("\(apps.count) apps available · installs to the selected bottle, then auto-imports.")
                    .font(.system(size: 11.5)).foregroundStyle(p.textSecondary)
            }
            Spacer()
            // bottle picker
            HStack(spacing: 6) {
                Image(systemName: "wineglass").font(.system(size: 11)).foregroundStyle(p.textSecondary)
                Picker("", selection: $bottleID) {
                    ForEach(library.bottles) { Text($0.shortLabel).tag($0.id) }
                }.labelsHidden().controlSize(.small).fixedSize()
            }
            // search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 12.5)).frame(width: 160)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(p.textSecondary)
                }
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.control))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.border, lineWidth: 0.5))

            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13)).frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.06))).foregroundStyle(p.textSecondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer(); ProgressView()
            Text("Loading the winetricks catalog…").font(.system(size: 12)).foregroundStyle(p.textSecondary)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var failedState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "wifi.exclamationmark").font(.system(size: 28)).foregroundStyle(p.textSecondary)
            Text("Couldn't load the catalog.").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text)
            Text("Wine may still be downloading, or winetricks couldn't run.")
                .font(.system(size: 12)).foregroundStyle(p.textSecondary).multilineTextAlignment(.center)
            Button("Try again") { if let b = bottle { wine.loadWinetricksCatalog(for: b) } }.controlSize(.small)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - install + auto-import

    private func existing(for verb: WinetricksVerb) -> Bool {
        let pretty = AppStoreNames.pretty(verb.name).lowercased()
        return library.apps.contains {
            $0.bottle == bottleID && ($0.name.lowercased() == pretty || $0.name.lowercased().contains(verb.name.lowercased()))
        }
    }

    private func install(_ verb: WinetricksVerb) {
        guard let b = bottle else { return }
        let prefix = wine.prefixURL(for: b.id)
        let before = Set(BottleScanner.scan(prefix: prefix).map(\.path))
        installing.insert(verb.name)
        let session = wine.runWinetricks(verbs: [verb.name], bottle: b) { ok in
            Task { @MainActor in
                installing.remove(verb.name)
                guard ok else { return }
                let after = BottleScanner.scan(prefix: prefix)
                let newApps = after.filter { !before.contains($0.path) }
                for app in newApps {
                    library.importFile(at: URL(fileURLWithPath: app.path), bottle: b.id)
                }
                if !newApps.isEmpty {
                    Notifier.notify("Installed \(AppStoreNames.pretty(verb.name))",
                                    "Added \(newApps.count) app\(newApps.count == 1 ? "" : "s") to your library.")
                }
            }
        }
        onConsole(session)
    }
}

// MARK: - Card

private struct AppStoreCard: View {
    @Environment(\.palette) private var p
    let verb: WinetricksVerb
    let accent: Color
    let busy: Bool
    let alreadyInstalled: Bool
    var onInstall: () -> Void

    @State private var hover = false

    private var pretty: String { AppStoreNames.pretty(verb.name) }
    private var preview: WineApp {
        let (g1, g2) = Theme.gradient(for: verb.name)
        let glyph = String(pretty.prefix(2)).uppercased()
        return WineApp(id: "preview-\(verb.name)", name: pretty, publisher: "", version: "",
                       bottle: "", arch: "x64", sizeBytes: 0, category: "Apps",
                       glyph: glyph, g1: g1, g2: g2, favorite: false, exePath: "", lastRun: nil)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconView(app: preview, size: 56, radius: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text(pretty).font(.system(size: 13.5, weight: .bold)).foregroundStyle(p.text).lineLimit(1)
                Text(verb.name).font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(p.textSecondary)
                Text(verb.description.isEmpty ? "—" : verb.description)
                    .font(.system(size: 11.5)).foregroundStyle(p.textSecondary).lineLimit(2)
                Spacer(minLength: 4)
                Button(action: onInstall) {
                    HStack(spacing: 4) {
                        if busy {
                            ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12)
                            Text("Installing…").font(.system(size: 11.5, weight: .semibold))
                        } else if alreadyInstalled {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                            Text("Installed").font(.system(size: 11.5, weight: .semibold))
                        } else {
                            Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold))
                            Text("Install").font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                    .foregroundStyle(alreadyInstalled ? p.text : Color.white)
                    .padding(.horizontal, 14).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(alreadyInstalled ? AnyShapeStyle(Color.gray.opacity(0.25))
                              : AnyShapeStyle(LinearGradient(colors: [accent, accent.darkened(0.22)],
                                                              startPoint: .top, endPoint: .bottom))))
                }
                .buttonStyle(.plain).disabled(busy || alreadyInstalled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(p.card)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(hover ? accent.opacity(0.45) : p.border, lineWidth: hover ? 1 : 0.5))
                .shadow(color: hover ? accent.opacity(0.15) : .black.opacity(p.isDark ? 0.3 : 0.08),
                        radius: hover ? 12 : 5, y: hover ? 6 : 3)
        }
        .offset(y: hover ? -2 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hover)
        .onHover { hover = $0 }
    }
}

// MARK: - Pretty names for popular winetricks app verbs

enum AppStoreNames {
    private static let map: [String: String] = [
        "7zip": "7-Zip",
        "autohotkey": "AutoHotkey",
        "firefox": "Firefox",
        "foobar2000": "foobar2000",
        "irfanview": "IrfanView",
        "kindle": "Amazon Kindle",
        "mpc": "Media Player Classic",
        "notepadplusplus": "Notepad++",
        "npp": "Notepad++",
        "office2007pro": "Microsoft Office 2007 Pro",
        "office2013pro": "Microsoft Office 2013 Pro",
        "openwatcom": "OpenWatcom",
        "origin": "EA Origin",
        "picasa39": "Picasa 3.9",
        "processhacker": "Process Hacker",
        "protontricks": "Protontricks",
        "qq": "Tencent QQ",
        "safari": "Safari",
        "sketchup": "SketchUp",
        "steam": "Steam",
        "utorrent": "µTorrent",
        "vc6": "Visual C++ 6.0",
        "vlc": "VLC media player",
        "winamp": "Winamp",
        "winrar": "WinRAR",
        "ie6": "Internet Explorer 6",
        "ie7": "Internet Explorer 7",
        "ie8": "Internet Explorer 8",
    ]
    static func pretty(_ verb: String) -> String {
        if let m = map[verb] { return m }
        return verb.prefix(1).uppercased() + verb.dropFirst()
    }
}
