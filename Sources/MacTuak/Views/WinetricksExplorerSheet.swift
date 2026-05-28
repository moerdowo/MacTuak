import SwiftUI

/// Browses the full winetricks catalog (DLLs, fonts, apps, settings, games,
/// benchmarks, prefix tweaks) and installs verbs into a chosen bottle.
struct WinetricksExplorerSheet: View {
    @EnvironmentObject var wine: WineManager
    @Environment(\.palette) private var p
    let bottle: Bottle
    let accent: Color
    var onConsole: (ConsoleSession) -> Void
    var onClose: () -> Void

    @State private var category: String = "dlls"
    @State private var query: String = ""

    private var current: WinetricksCategory? {
        wine.winetricksCatalog.first { $0.name == category }
    }
    private var filteredVerbs: [WinetricksVerb] {
        guard let list = current?.verbs else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return list }
        return list.filter { $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                HStack(spacing: 0) {
                    categoryList
                    Rectangle().fill(p.separator).frame(width: 0.5)
                    verbList
                }.frame(height: 480)
            }
            .frame(width: 780)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 24)
        }
        .onAppear {
            wine.loadWinetricksCatalog(for: bottle)
            if let first = wine.winetricksCatalog.first { category = first.name }
        }
        .onChange(of: wine.winetricksCatalog.map { $0.name }) { _, names in
            if !names.contains(category), let first = names.first { category = first }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Winetricks Browser").font(.system(size: 15, weight: .bold)).foregroundStyle(p.text)
                Text("Bottle \(bottle.shortLabel)").font(.system(size: 11.5)).foregroundStyle(p.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                TextField("Search verbs", text: $query).textFieldStyle(.plain).font(.system(size: 12.5))
                    .frame(width: 180)
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
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }
    }

    // MARK: category list

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Winetricks.categories, id: \.name) { cat in
                    let cnt = wine.winetricksCatalog.first { $0.name == cat.name }?.verbs.count ?? 0
                    Button { category = cat.name } label: {
                        HStack(spacing: 8) {
                            Image(systemName: cat.system).font(.system(size: 12))
                            Text(cat.label).font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                            if cnt > 0 {
                                Text("\(cnt)").font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(category == cat.name ? .white.opacity(0.85) : p.textSecondary)
                            }
                        }
                        .foregroundStyle(category == cat.name ? .white : p.text)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(category == cat.name ? AnyShapeStyle(accent) : AnyShapeStyle(Color.clear)))
                    }.buttonStyle(.plain)
                }
            }.padding(8)
        }
        .frame(width: 180)
        .background(p.sidebarBG)
    }

    // MARK: verb list

    private var verbList: some View {
        Group {
            if wine.catalogLoading && wine.winetricksCatalog.isEmpty {
                VStack(spacing: 10) {
                    Spacer(); ProgressView(); Text("Loading verbs from winetricks…")
                        .font(.system(size: 12)).foregroundStyle(p.textSecondary); Spacer()
                }
            } else if wine.winetricksCatalog.isEmpty {
                VStack {
                    Spacer()
                    Text("Couldn't load the winetricks catalog.")
                        .font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    Button("Try again") { wine.loadWinetricksCatalog(for: bottle) }.controlSize(.small).padding(.top, 6)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredVerbs) { verb in
                            VerbRow(verb: verb, accent: accent) { onConsole(wine.runWinetricks(verbs: [verb.name], bottle: bottle)) }
                        }
                        if filteredVerbs.isEmpty {
                            Text("No matches in \(current?.label ?? "this category").")
                                .font(.system(size: 12)).foregroundStyle(p.textSecondary).padding(30)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct VerbRow: View {
    @Environment(\.palette) private var p
    let verb: WinetricksVerb
    let accent: Color
    var onInstall: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verb.name).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(p.text)
                Text(verb.description.isEmpty ? "—" : verb.description)
                    .font(.system(size: 11.5)).foregroundStyle(p.textSecondary).lineLimit(2)
            }
            Spacer()
            Button(action: onInstall) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 11))
                    Text("Install").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white).padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(accent))
            }
            .buttonStyle(.plain)
            .opacity(hover ? 1 : 0.85)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(hover ? (p.isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
