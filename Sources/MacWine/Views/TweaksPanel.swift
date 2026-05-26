import SwiftUI

/// The design's "Tweaks" panel, surfaced natively as a popover from a toolbar button.
struct TweaksButton: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var wine: WineManager
    @Environment(\.palette) private var p
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .medium))
                .foregroundStyle(p.text)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .solidSurface(RoundedRectangle(cornerRadius: 10, style: .continuous), p)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            TweaksContent()
                .environmentObject(settings).environmentObject(wine)
                .environment(\.palette, p)
                .frame(width: 280)
        }
    }
}

private struct TweaksContent: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var wine: WineManager

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

            section("Library")
            picker("View", selection: Binding(get: { settings.view }, set: { settings.view = $0 }),
                   options: [("grid", "Grid"), ("list", "List")])

            section("Wine Runtime")
            HStack(alignment: .top, spacing: 8) {
                Text(wine.runtime.statusText).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
            }
            Button {
                wine.checkForUpdate(force: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    Text(wine.runtime.isBusy ? "Working…" : "Check for update").font(.system(size: 12, weight: .medium))
                }
            }
            .disabled(wine.runtime.isBusy)
            .controlSize(.small)
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
