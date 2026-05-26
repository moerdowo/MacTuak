import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Edit an existing app's name, path, bottle, category, and icon.
struct EditAppSheet: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.palette) private var p
    let app: WineApp
    let accent: Color
    var onClose: () -> Void

    @State private var name: String
    @State private var path: String
    @State private var bottle: String
    @State private var category: String
    @State private var arch: String
    @State private var opts: LaunchOptions
    @State private var iconChoice: IconChoice

    init(app: WineApp, accent: Color, onClose: @escaping () -> Void) {
        self.app = app
        self.accent = accent
        self.onClose = onClose
        _name = State(initialValue: app.name)
        _path = State(initialValue: app.exePath)
        _bottle = State(initialValue: app.bottle)
        _category = State(initialValue: app.category)
        _arch = State(initialValue: app.arch)
        _opts = State(initialValue: app.opts)
        _iconChoice = State(initialValue: app.iconFileName == nil ? .removed : .keepExisting)
    }

    private var noIconApp: WineApp { var a = app; a.iconFileName = nil; a.name = name; return a }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                // header
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [accent, accent.darkened(0.3)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 32, height: 32)
                        .overlay(Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("App Info").font(.system(size: 15, weight: .bold)).foregroundStyle(p.text)
                        Text("Edit name, path, bottle, category, and icon.").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                            .foregroundStyle(p.textSecondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12)

                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        IconWell(choice: $iconChoice, existingURL: app.iconURL, accent: accent, size: 64) {
                            AppIconView(app: noIconApp, size: 64, radius: 16)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("App Icon").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text)
                            Text("Pick a PNG/JPG, remove for the generated icon, or pull it from the .exe.")
                                .font(.system(size: 11.5)).foregroundStyle(p.textSecondary)
                            Button {
                                if let img = PEInfo.icon(of: (path as NSString).expandingTildeInPath) {
                                    iconChoice = .custom(img)
                                }
                            } label: {
                                Label("Extract from .exe", systemImage: "wand.and.stars").font(.system(size: 11.5, weight: .semibold))
                            }.buttonStyle(.plain).foregroundStyle(accent)
                        }
                        Spacer()
                    }

                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                        field("Name", text: $name, placeholder: "App name")
                        GridRow {
                            Text("Path").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textSecondary)
                            HStack(spacing: 6) {
                                TextField("~/path/to/App.exe", text: $path)
                                    .textFieldStyle(.plain).font(.system(size: 13))
                                    .padding(.horizontal, 10).frame(height: 28)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.control))
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
                                Button("Browse…") { browse() }.controlSize(.small)
                            }
                        }
                        GridRow {
                            Text("Bottle").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textSecondary)
                            Picker("", selection: $bottle) {
                                ForEach(library.bottles) { b in Text(b.label).tag(b.id) }
                            }.labelsHidden().controlSize(.small)
                        }
                        GridRow {
                            Text("Category").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textSecondary)
                            Picker("", selection: $category) {
                                ForEach(Theme.categories.filter { $0 != "All" }, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().controlSize(.small)
                        }
                        GridRow {
                            Text("Arch").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textSecondary)
                            Picker("", selection: $arch) { Text("64-bit").tag("x64"); Text("32-bit").tag("x86") }
                                .labelsHidden().pickerStyle(.segmented).controlSize(.small).fixedSize()
                        }
                    }

                    launchOptions
                }
                .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 14)

                // footer
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel", action: onClose)
                        .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.text)
                        .padding(.horizontal, 14).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                    Button(action: save) {
                        Text("Save Changes").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(name.isEmpty ? AnyShapeStyle(Color.primary.opacity(0.12))
                                      : AnyShapeStyle(LinearGradient(colors: [accent, accent.darkened(0.22)], startPoint: .top, endPoint: .bottom))))
                    }
                    .buttonStyle(.plain).disabled(name.isEmpty).opacity(name.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color.primary.opacity(0.04))
                .overlay(alignment: .top) { Rectangle().fill(p.separator).frame(height: 0.5) }
            }
            .frame(width: 480)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.30), radius: 40, y: 24)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private var launchOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAUNCH OPTIONS").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(p.textSecondary)
                .padding(.top, 4)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                field("Arguments", text: $opts.arguments, placeholder: "--fullscreen")
                field("Working dir", text: $opts.workingDir, placeholder: "(defaults to .exe folder)")
                field("WINEDEBUG", text: $opts.winedebug, placeholder: "-all to silence")
                GridRow {
                    Text("Virtual desktop").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textSecondary)
                    TextField("off — e.g. 1280x720", text: $opts.virtualDesktop)
                        .textFieldStyle(.plain).font(.system(size: 13)).padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(p.control))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(p.border, lineWidth: 0.5))
                }
                GridRow {
                    Text("Environment").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textSecondary)
                    TextField("KEY=VALUE per line", text: $opts.environment, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain).font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(p.control))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(p.border, lineWidth: 0.5))
                }
            }
            HStack(spacing: 18) {
                Toggle("Esync", isOn: $opts.esync).toggleStyle(.checkbox).font(.system(size: 12))
                Toggle("Retina / HiDPI", isOn: $opts.retina).toggleStyle(.checkbox).font(.system(size: 12))
                Spacer()
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        GridRow {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.control))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data, .folder, .application]
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }

    private func save() {
        guard !name.isEmpty else { return }
        var u = app
        u.name = name.replacingOccurrences(of: ".exe", with: "", options: .caseInsensitive)
        u.exePath = (path as NSString).expandingTildeInPath
        u.bottle = bottle
        u.category = category
        u.arch = arch
        u.opts = opts
        switch iconChoice {
        case .custom(let img):
            library.deleteIcon(named: u.iconFileName)
            u.iconFileName = library.writeIcon(img, appID: u.id)
        case .removed:
            library.deleteIcon(named: u.iconFileName)
            u.iconFileName = nil
        case .keepExisting:
            break
        }
        library.update(u)
        onClose()
    }
}
