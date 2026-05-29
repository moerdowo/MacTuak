import SwiftUI

/// Edits `HKCU\Software\Wine\DllOverrides`. Common values are
/// `native`, `builtin`, `native,builtin`, `builtin,native`, `disabled`.
struct DllOverridesSheet: View {
    @EnvironmentObject var wine: WineManager
    @Environment(\.palette) private var p
    let bottle: Bottle
    let accent: Color
    var onConsole: (ConsoleSession) -> Void
    var onClose: () -> Void

    @State private var entries: [(dll: String, value: String)] = []
    @State private var loading = true
    @State private var newDll = ""
    @State private var newValue = "native"

    private let presetValues = ["native", "builtin", "native,builtin", "builtin,native", "disabled"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.below.ecg").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DLL Overrides").font(.system(size: 15, weight: .bold)).foregroundStyle(p.text)
                        Text("HKCU\\Software\\Wine\\DllOverrides · \(bottle.shortLabel)")
                            .font(.system(size: 11)).foregroundStyle(p.textSecondary)
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

                if loading {
                    VStack { Spacer(); ProgressView(); Text("Reading registry…").font(.system(size: 12)).foregroundStyle(p.textSecondary); Spacer() }
                        .frame(height: 340)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            if entries.isEmpty {
                                Text("No overrides set. Wine builtins take effect everywhere by default.")
                                    .font(.system(size: 12)).foregroundStyle(p.textSecondary).padding(20)
                            }
                            ForEach(entries, id: \.dll) { entry in row(entry) }
                        }.padding(12)
                    }.frame(height: 280)
                }

                // Add row
                HStack(spacing: 6) {
                    TextField("d3d11", text: $newDll)
                        .textFieldStyle(.plain).font(.system(size: 12.5, design: .monospaced))
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(p.control))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.border, lineWidth: 0.5))
                        .frame(width: 140)
                    Picker("", selection: $newValue) {
                        ForEach(presetValues, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().controlSize(.small).fixedSize()
                    Spacer()
                    Button("Add override") {
                        let name = newDll.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        onConsole(wine.setDllOverride(bottle: bottle, dll: name, value: newValue))
                        newDll = ""
                        // Refresh after a beat
                        Task { try? await Task.sleep(nanoseconds: 800_000_000); reload() }
                    }
                    .controlSize(.small)
                    .disabled(newDll.isEmpty)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04))
                .overlay(alignment: .top) { Rectangle().fill(p.separator).frame(height: 0.5) }
            }
            .frame(width: 580)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 24)
        }
        .task { reload() }
    }

    private func reload() {
        loading = true
        Task {
            let list = await wine.queryDllOverrides(bottle: bottle)
            await MainActor.run {
                entries = list.sorted { $0.dll < $1.dll }
                loading = false
            }
        }
    }

    private func row(_ entry: (dll: String, value: String)) -> some View {
        HStack(spacing: 10) {
            Text(entry.dll).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).foregroundStyle(p.text)
                .frame(width: 160, alignment: .leading)
            Text(entry.value).font(.system(size: 12, design: .monospaced)).foregroundStyle(p.textSecondary)
            Spacer()
            Menu {
                ForEach(presetValues, id: \.self) { v in
                    Button(v) { onConsole(wine.setDllOverride(bottle: bottle, dll: entry.dll, value: v));
                        Task { try? await Task.sleep(nanoseconds: 800_000_000); reload() } }
                }
            } label: { Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(p.text) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            Button {
                onConsole(wine.setDllOverride(bottle: bottle, dll: entry.dll, value: ""))
                Task { try? await Task.sleep(nanoseconds: 800_000_000); reload() }
            } label: { Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Color(hex: "#ff453a")) }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(p.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.border, lineWidth: 0.5))
    }
}
