import SwiftUI

/// The design's "Tweaks" panel, surfaced natively as a popover from a toolbar button.
struct TweaksButton: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var library: LibraryStore
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .background(Color.clear.liquidGlass(RoundedRectangle(cornerRadius: 10, style: .continuous), interactive: true))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            TweaksContent().environmentObject(settings).environmentObject(library)
                .frame(width: 260)
        }
    }
}

private struct TweaksContent: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Appearance")
            HStack {
                Text("Accent").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Theme.accentOptions, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(.primary.opacity(settings.accent == hex ? 0.85 : 0.1),
                                                           lineWidth: settings.accent == hex ? 2 : 0.5))
                            .onTapGesture { settings.accent = hex }
                    }
                }
            }
            picker("Theme", selection: Binding(get: { settings.dark ? "dark" : "light" },
                                               set: { settings.dark = ($0 == "dark") }),
                   options: [("light", "Light"), ("dark", "Dark")])
            picker("Wallpaper", selection: Binding(get: { settings.wallpaper }, set: { settings.wallpaper = $0 }),
                   options: [("sunset", "Sunset"), ("ocean", "Ocean"), ("forest", "Forest"), ("graphite", "Graphite")])
            Toggle("Animate wallpaper", isOn: Binding(get: { settings.animateWallpaper }, set: { settings.animateWallpaper = $0 }))
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))

            section("Library")
            picker("View", selection: Binding(get: { settings.view }, set: { settings.view = $0 }),
                   options: [("grid", "Grid"), ("list", "List")])
        }
        .padding(16)
    }

    private func section(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
    }

    private func picker(_ label: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden().pickerStyle(.segmented).controlSize(.small).fixedSize()
        }
    }
}
