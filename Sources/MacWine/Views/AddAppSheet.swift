import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct AddAppSheet: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var settings: Settings
    let accent: Color
    /// Pre-filled URL when the sheet was opened from a window drop.
    var prefilled: URL?
    var onClose: () -> Void
    var onAdded: (WineApp) -> Void

    @State private var name = ""
    @State private var path = ""
    @State private var bottle = "win10-x64"
    @State private var dragHover = false
    @State private var pickedURL: URL?

    var body: some View {
        ZStack {
            Color.black.opacity(0.40).ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                // header
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [accent, accent.darkened(0.3)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 32, height: 32)
                        .overlay(Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Add Windows Application").font(.system(size: 15, weight: .bold))
                        Text("Drop a .exe, pick a folder, or paste a path.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                            .foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 8)

                VStack(spacing: 14) {
                    // drop zone
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(dragHover ? accent : Color.primary.opacity(0.06))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "square.and.arrow.up").font(.system(size: 20))
                                .foregroundStyle(dragHover ? .white : accent))
                        Text("Drop .exe or folder here").font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 4) {
                            Text("or").font(.system(size: 11.5)).foregroundStyle(.secondary)
                            Button("browse your Mac…") { browse() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(22)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.03)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .foregroundStyle(dragHover ? accent : Color.primary.opacity(0.18)))
                    .onDrop(of: [.fileURL], isTargeted: $dragHover) { providers in
                        loadDrop(providers); return true
                    }

                    // fields
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                        field("Name", text: $name, placeholder: "MyApp.exe")
                        field("Path", text: $path, placeholder: "~/Downloads/Setup.exe")
                        GridRow {
                            Text("Bottle").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            Picker("", selection: $bottle) {
                                ForEach(library.bottles) { b in Text(b.label).tag(b.id) }
                            }
                            .labelsHidden().controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)

                // footer
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel", action: onClose)
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                    Button(action: submit) {
                        Text("Add to Library").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(name.isEmpty ? AnyShapeStyle(Color.primary.opacity(0.12))
                                      : AnyShapeStyle(LinearGradient(colors: [accent, accent.darkened(0.22)], startPoint: .top, endPoint: .bottom))))
                    }
                    .buttonStyle(.plain).disabled(name.isEmpty).opacity(name.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color.primary.opacity(0.04))
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5) }
            }
            .frame(width: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.30), radius: 40, y: 24)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
        .onAppear {
            bottle = library.bottles.first?.id ?? "win10-x64"
            if let prefilled { apply(prefilled) }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        GridRow {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.background.opacity(0.9)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
        }
    }

    // MARK: - Actions

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data, .folder, .application]
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url { apply(url) }
    }

    private func loadDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in apply(url) }
        }
    }

    private func apply(_ url: URL) {
        pickedURL = url
        name = url.lastPathComponent
        path = url.path
    }

    private func submit() {
        guard !name.isEmpty else { return }
        let url = pickedURL ?? URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var app: WineApp
        if FileManager.default.fileExists(atPath: url.path) {
            app = WineApp.imported(from: url, bottle: bottle)
            app.name = name.replacingOccurrences(of: ".exe", with: "", options: .caseInsensitive)
        } else {
            // Manual entry without a real file — still create a library record.
            let (g1, g2) = Theme.gradient(for: name)
            app = WineApp(id: "app-\(UUID().uuidString.prefix(8))",
                          name: name.replacingOccurrences(of: ".exe", with: "", options: .caseInsensitive),
                          publisher: "Custom", version: "1.0", bottle: bottle, arch: "x64",
                          sizeBytes: 0, category: "Utilities",
                          glyph: String(name.prefix(2)).uppercased(), g1: g1, g2: g2,
                          favorite: false, exePath: (path as NSString).expandingTildeInPath, lastRun: nil)
        }
        library.add(app)
        onAdded(app)
        onClose()
    }
}

struct DropOverlay: View {
    let accent: Color
    var body: some View {
        ZStack {
            accent.opacity(0.13).ignoresSafeArea().background(.ultraThinMaterial)
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [accent, accent.darkened(0.3)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "square.and.arrow.up").font(.system(size: 26)).foregroundStyle(.white))
                    .shadow(color: accent.opacity(0.5), radius: 12)
                Text("Drop to install").font(.system(size: 16, weight: .bold))
                Text("Drop a .exe or folder to add it to your library.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            .padding(32).frame(width: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(accent, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
        }
        .allowsHitTesting(false)
    }
}

struct UninstallToast: View {
    let app: WineApp
    let accent: Color
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(app: app, size: 28, radius: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(app.name) uninstalled").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text("Removed from bottle · \(app.sizeDisplay) freed").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Button("Undo", action: onUndo)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(accent)
                .padding(.horizontal, 8).frame(height: 28)
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
        .background(Color(hex: "#282830").opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
