import SwiftUI

/// Browses and edits a bottle's wine registry. Reads via `wine reg query`,
/// writes via `wine reg add` / `wine reg delete`. Stays per-prefix.
struct RegistryEditorSheet: View {
    @EnvironmentObject var wine: WineManager
    @Environment(\.palette) private var p
    let bottle: Bottle
    let accent: Color
    var onConsole: (ConsoleSession) -> Void
    var onClose: () -> Void

    /// Commonly-tweaked keys; users can also browse arbitrary paths via the field.
    private let presetKeys: [(label: String, path: String)] = [
        ("Wine — Mac Driver",         "HKCU\\Software\\Wine\\Mac Driver"),
        ("Wine — Direct3D",           "HKCU\\Software\\Wine\\Direct3D"),
        ("Wine — X11 Driver",         "HKCU\\Software\\Wine\\X11 Driver"),
        ("DLL Overrides",             "HKCU\\Software\\Wine\\DllOverrides"),
        ("Environment",               "HKCU\\Environment"),
        ("Windows version (NT)",      "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion"),
        ("Locale",                    "HKCU\\Control Panel\\International"),
    ]

    @State private var currentPath = "HKCU\\Software\\Wine"
    @State private var values: [(name: String, type: String, data: String)] = []
    @State private var loading = false
    @State private var newName = ""
    @State private var newValue = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                HStack(spacing: 0) {
                    sidebar
                    Rectangle().fill(p.separator).frame(width: 0.5)
                    detail
                }.frame(height: 420)
            }
            .frame(width: 720)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 24)
        }
        .task { reload() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3").foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Registry").font(.system(size: 15, weight: .bold)).foregroundStyle(p.text)
                Text("Bottle \(bottle.shortLabel)").font(.system(size: 11)).foregroundStyle(p.textSecondary)
            }
            Spacer()
            Button(action: reload) { Image(systemName: "arrow.clockwise").foregroundStyle(p.textSecondary) }.buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13)).frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.06))).foregroundStyle(p.textSecondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(presetKeys, id: \.path) { item in
                        Button { currentPath = item.path; reload() } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.label).font(.system(size: 12.5, weight: .semibold))
                                Text(item.path).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(p.textSecondary).lineLimit(1).truncationMode(.middle)
                            }
                            .foregroundStyle(currentPath == item.path ? Color.white : p.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(currentPath == item.path ? AnyShapeStyle(accent) : AnyShapeStyle(Color.clear)))
                        }.buttonStyle(.plain)
                    }
                }.padding(8)
            }
            HStack(spacing: 4) {
                TextField("HKCU\\Software\\Wine\\Direct3D", text: $currentPath, onCommit: reload)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(p.control))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.border, lineWidth: 0.5))
                Button("Go", action: reload).controlSize(.small)
            }.padding(8).background(Color.primary.opacity(0.03))
        }
        .frame(width: 250).background(p.sidebarBG)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            Group {
                if loading {
                    VStack { Spacer(); ProgressView(); Spacer() }
                } else if values.isEmpty {
                    VStack { Spacer(); Text("(no values)").foregroundStyle(p.textSecondary); Spacer() }
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(values, id: \.name) { v in valueRow(v) }
                        }.padding(12)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                TextField("ValueName", text: $newName)
                    .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(p.control))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.border, lineWidth: 0.5))
                    .frame(width: 140)
                TextField("data (string)", text: $newValue)
                    .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(p.control))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.border, lineWidth: 0.5))
                Button("Set") {
                    onConsole(wine.regAdd(bottle: bottle, key: currentPath, name: newName, data: newValue))
                    Task { try? await Task.sleep(nanoseconds: 800_000_000); reload() }
                }
                .controlSize(.small).disabled(newName.isEmpty)
            }
            .padding(12).background(Color.primary.opacity(0.04))
            .overlay(alignment: .top) { Rectangle().fill(p.separator).frame(height: 0.5) }
        }
    }

    private func valueRow(_ v: (name: String, type: String, data: String)) -> some View {
        HStack(spacing: 10) {
            Text(v.name).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(p.text)
                .frame(width: 160, alignment: .leading)
            Text(v.type).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(p.textSecondary).frame(width: 60, alignment: .leading)
            Text(v.data).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(p.text).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Button {
                onConsole(wine.regDelete(bottle: bottle, key: currentPath, name: v.name))
                Task { try? await Task.sleep(nanoseconds: 800_000_000); reload() }
            } label: { Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Color(hex: "#ff453a")) }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(p.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.border, lineWidth: 0.5))
    }

    private func reload() {
        loading = true
        Task {
            let result = await wine.regQuery(bottle: bottle, key: currentPath)
            await MainActor.run {
                values = result
                loading = false
            }
        }
    }
}
