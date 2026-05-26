import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var settings: Settings
    @Binding var section: String
    var onAdd: () -> Void

    var body: some View {
        let accent = settings.accentColor
        let counts = library.counts

        VStack(spacing: 0) {
            // header — leaves room for the native traffic lights at top-left
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [accent, accent.darkened(0.4)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 20, height: 20)
                    .overlay(Image(systemName: "wineglass.fill")
                        .font(.system(size: 11)).foregroundStyle(.white))
                    .shadow(color: accent.opacity(0.33), radius: 2, y: 1)
                Text("MacWine").font(.system(size: 13, weight: .bold))
                Spacer()
            }
            .padding(.leading, 78)   // clears the traffic lights
            .padding(.trailing, 14)
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 0) {
                    SidebarSectionHeader(text: "Library")
                    row(.init("All Apps", "square.grid.2x2", "library:All", counts["All"]))
                    row(.init("Running", "play.fill", "library:Running",
                              (counts["Running"] ?? 0) > 0 ? counts["Running"] : nil))
                    row(.init("Favorites", "star", "library:Favorites", counts["Favorites"]))
                    row(.init("Recent", "clock", "library:Recent", nil))

                    SidebarSectionHeader(text: "Categories")
                    ForEach(Theme.categories.filter { $0 != "All" }, id: \.self) { cat in
                        SidebarRow(icon: { CategoryDot(category: cat) }, label: cat,
                                   count: (counts[cat] ?? 0) > 0 ? counts[cat] : nil,
                                   selected: section == "library:\(cat)", accent: accent) {
                            section = "library:\(cat)"
                        }
                    }

                    SidebarSectionHeader(text: "Wine Bottles")
                    ForEach(library.bottles) { b in
                        SidebarRow(icon: { Image(systemName: "wineglass").font(.system(size: 13)) },
                                   label: b.shortLabel,
                                   count: library.bottleAppCount(b.id),
                                   selected: section == "bottle:\(b.id)", accent: accent) {
                            section = "bottle:\(b.id)"
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            // add button
            Button(action: onAdd) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                    Text("Add Application").font(.system(size: 12.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity).frame(height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(Color.clear.liquidGlass(RoundedRectangle(cornerRadius: 9, style: .continuous), interactive: true))
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 14)
        }
        .frame(width: 240)
        .background(.regularMaterial.opacity(0.6))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.12)).frame(width: 0.5)
        }
    }

    private struct Entry {
        let label: String, system: String, key: String
        let count: Int?
        init(_ label: String, _ system: String, _ key: String, _ count: Int?) {
            self.label = label; self.system = system; self.key = key; self.count = count
        }
    }

    private func row(_ e: Entry) -> some View {
        SidebarRow(icon: { Image(systemName: e.system).font(.system(size: 13)) },
                   label: e.label, count: e.count,
                   selected: section == e.key, accent: settings.accentColor) {
            section = e.key
        }
    }
}
