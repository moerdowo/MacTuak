import SwiftUI

struct SteamImporterSheet: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.palette) private var p
    let bottle: Bottle
    let accent: Color
    var onClose: () -> Void

    @State private var loading = true
    @State private var games: [SteamGame] = []
    @State private var selected = Set<String>()

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "gamecontroller").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Import from Steam").font(.system(size: 15, weight: .bold)).foregroundStyle(p.text)
                        Text("Scanning ~/Library/Application Support/Steam → bottle \(bottle.shortLabel)")
                            .font(.system(size: 11)).foregroundStyle(p.textSecondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13)).frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.06))).foregroundStyle(p.textSecondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }

                if loading {
                    VStack { Spacer(); ProgressView(); Text("Scanning Steam libraries…").font(.system(size: 12)).foregroundStyle(p.textSecondary); Spacer() }
                        .frame(height: 360)
                } else if games.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundStyle(p.textSecondary)
                        Text("No Windows games found in your Steam libraries.")
                            .font(.system(size: 12.5)).foregroundStyle(p.text)
                        Text("Native macOS games and titles without `.exe` files are skipped.")
                            .font(.system(size: 11)).foregroundStyle(p.textSecondary)
                        Spacer()
                    }.frame(height: 360)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(games) { g in
                                Toggle(isOn: Binding(get: { selected.contains(g.id) },
                                                     set: { on in if on { selected.insert(g.id) } else { selected.remove(g.id) } })) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(g.game).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.text)
                                        Text((g.exePath as NSString).lastPathComponent)
                                            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(p.textSecondary)
                                    }
                                }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(12)
                    }.frame(height: 360)
                }

                HStack {
                    Text(games.isEmpty ? " " : "\(selected.count) selected")
                        .font(.system(size: 11)).foregroundStyle(p.textSecondary)
                    Spacer()
                    Button("Cancel", action: onClose)
                    Button("Import \(selected.count)") {
                        for g in games where selected.contains(g.id) {
                            library.importFile(at: URL(fileURLWithPath: g.exePath), bottle: bottle.id)
                        }
                        onClose()
                    }.keyboardShortcut(.defaultAction).disabled(selected.isEmpty)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(p.separator).frame(height: 0.5) }
            }
            .frame(width: 580)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 24)
        }
        .task {
            let result = await Task.detached { SteamScanner.scan() }.value
            await MainActor.run { games = result; loading = false }
        }
    }
}
