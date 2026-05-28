import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BottleManagerSheet: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var wine: WineManager
    @Environment(\.palette) private var p
    let accent: Color
    var onClose: () -> Void

    @State private var selection: String?
    @State private var console: ConsoleSession?
    @State private var scanResults: [ScannedApp]?
    @State private var confirmReset = false
    @State private var confirmDelete = false
    @State private var newBottle = false
    @State private var showExplorer = false

    private var selected: Bottle? { library.bottles.first { $0.id == selection } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "wineglass.fill").foregroundStyle(accent)
                    Text("Wine Bottles").font(.system(size: 15, weight: .bold)).foregroundStyle(p.text)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13)).frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.06))).foregroundStyle(p.textSecondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }

                HStack(spacing: 0) {
                    bottleList
                    Rectangle().fill(p.separator).frame(width: 0.5)
                    detail
                }
                .frame(height: 440)
            }
            .frame(width: 680)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 24)

            if let console {
                ConsoleSheet(session: console) { self.console = nil }.zIndex(10)
            }
            if let scanResults {
                ScanImporterSheet(apps: scanResults, bottleID: selection ?? "", accent: accent) {
                    self.scanResults = nil
                }.zIndex(10)
            }
            if newBottle {
                NewBottleSheet(accent: accent) { label, ver, arch, installRuntimes in
                    let b = library.addBottle(label: label, windowsVersion: ver, arch: arch)
                    selection = b.id
                    console = wine.initBottle(b, applyVersion: true, installRuntimes: installRuntimes)
                    newBottle = false
                } onCancel: { newBottle = false }.zIndex(10)
            }
            if showExplorer, let b = selected {
                WinetricksExplorerSheet(bottle: b, accent: accent,
                                        onConsole: { console = $0 },
                                        onClose: { showExplorer = false })
                    .zIndex(5)
            }
        }
        .onAppear { if selection == nil { selection = library.bottles.first?.id } }
    }

    // MARK: list

    private var bottleList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(library.bottles) { b in
                        Button { selection = b.id } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "wineglass").font(.system(size: 12)).foregroundStyle(selection == b.id ? .white : p.textSecondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(b.shortLabel).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                    Text("\(library.bottleAppCount(b.id)) apps").font(.system(size: 10.5))
                                        .foregroundStyle(selection == b.id ? .white.opacity(0.8) : p.textSecondary)
                                }
                                Spacer()
                            }
                            .foregroundStyle(selection == b.id ? .white : p.text)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == b.id ? AnyShapeStyle(accent) : AnyShapeStyle(Color.clear)))
                        }.buttonStyle(.plain)
                    }
                }.padding(8)
            }
            Button { newBottle = true } label: {
                HStack(spacing: 6) { Image(systemName: "plus"); Text("New Bottle").font(.system(size: 12, weight: .semibold)) }
                    .frame(maxWidth: .infinity).frame(height: 30).foregroundStyle(p.text)
            }
            .buttonStyle(.plain)
            .solidSurface(RoundedRectangle(cornerRadius: 8, style: .continuous), p)
            .padding(8)
        }
        .frame(width: 220)
        .background(p.sidebarBG)
    }

    // MARK: detail

    @ViewBuilder private var detail: some View {
        if let b = selected {
            BottleDetail(bottle: b, accent: accent,
                         onConsole: { console = $0 },
                         onScan: { scanResults = BottleScanner.scan(prefix: wine.prefixURL(for: b.id)) },
                         onBrowse: { showExplorer = true },
                         onReset: { confirmReset = true },
                         onDelete: { confirmDelete = true })
                .id(b.id)
                .confirmationDialog("Reset \(b.shortLabel)? This erases the bottle's C: drive and installed software.",
                                    isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Reset Bottle", role: .destructive) {
                        wine.deletePrefix(bottleID: b.id)
                        console = wine.initBottle(b)
                    }
                }
                .confirmationDialog("Delete \(b.shortLabel)? Apps in it move to another bottle; files are removed.",
                                    isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete Bottle", role: .destructive) {
                        wine.deletePrefix(bottleID: b.id)
                        library.deleteBottle(b.id)
                        selection = library.bottles.first?.id
                    }
                }
        } else {
            VStack { Spacer(); Text("No bottle selected").foregroundStyle(p.textSecondary); Spacer() }
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Detail pane

private struct BottleDetail: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var wine: WineManager
    @Environment(\.palette) private var p
    let bottle: Bottle
    let accent: Color
    var onConsole: (ConsoleSession) -> Void
    var onScan: () -> Void
    var onBrowse: () -> Void
    var onReset: () -> Void
    var onDelete: () -> Void

    @State private var label: String
    @State private var winVer: String
    @State private var disk = "…"
    @State private var verbs: Set<String> = []

    init(bottle: Bottle, accent: Color, onConsole: @escaping (ConsoleSession) -> Void,
         onScan: @escaping () -> Void, onBrowse: @escaping () -> Void,
         onReset: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.bottle = bottle; self.accent = accent
        self.onConsole = onConsole; self.onScan = onScan; self.onBrowse = onBrowse
        self.onReset = onReset; self.onDelete = onDelete
        _label = State(initialValue: bottle.label)
        _winVer = State(initialValue: bottle.winVersion)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // identity
                VStack(alignment: .leading, spacing: 6) {
                    Text("NAME").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(p.textSecondary)
                    HStack {
                        TextField("Bottle name", text: $label, onCommit: { library.renameBottle(bottle.id, to: label) })
                            .textFieldStyle(.plain).font(.system(size: 13))
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(p.control))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(p.border, lineWidth: 0.5))
                        Button("Rename") { library.renameBottle(bottle.id, to: label) }.controlSize(.small)
                    }
                }

                HStack(spacing: 18) {
                    info("Arch", bottle.winArch == "win64" ? "64-bit" : "32-bit")
                    info("Apps", "\(library.bottleAppCount(bottle.id))")
                    info("Disk", disk)
                    info("Wine", bottle.wineVersion)
                }

                HStack {
                    Text("Windows").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textSecondary)
                    Picker("", selection: $winVer) {
                        ForEach(Bottle.windowsVersionOptions, id: \.self) {
                            Text(["win7": "Windows 7", "win10": "Windows 10", "win11": "Windows 11"][$0] ?? $0).tag($0)
                        }
                    }.labelsHidden().controlSize(.small).fixedSize()
                    Button("Apply") {
                        var b = bottle; b.windowsVersion = winVer; library.updateBottle(b)
                        onConsole(wine.setWindowsVersion(b))
                    }.controlSize(.small).disabled(winVer == bottle.winVersion)
                    Spacer()
                }

                Divider()

                // tools
                Text("TOOLS").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(p.textSecondary)
                WrapButtons {
                    toolButton("Install Software…", "tray.and.arrow.down") { chooseInstaller() }
                    toolButton("Initialize / Repair", "arrow.clockwise") { onConsole(wine.initBottle(bottle)) }
                    toolButton("winecfg", "gearshape") { wine.runTool("winecfg", bottle: bottle) }
                    toolButton("regedit", "square.grid.3x3") { wine.runTool("regedit", bottle: bottle) }
                    toolButton("Control Panel", "slider.horizontal.3") { wine.runTool("control", bottle: bottle) }
                    toolButton("Open C: Drive", "folder") { wine.openDriveC(bottle: bottle) }
                    toolButton("Scan for Apps", "magnifyingglass") { onScan() }
                    toolButton("Browse winetricks…", "puzzlepiece.extension") { onBrowse() }
                    toolButton("Install common runtimes", "shippingbox.fill") {
                        onConsole(wine.runWinetricks(verbs: Winetricks.coreRuntimeVerbs, bottle: bottle))
                    }
                }

                Divider()

                // winetricks
                Text("WINETRICKS COMPONENTS").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(p.textSecondary)
                VStack(spacing: 4) {
                    ForEach(Winetricks.commonVerbs, id: \.verb) { item in
                        Toggle(isOn: Binding(get: { verbs.contains(item.verb) },
                                             set: { if $0 { verbs.insert(item.verb) } else { verbs.remove(item.verb) } })) {
                            Text(item.label).font(.system(size: 12))
                        }.toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button {
                    onConsole(wine.runWinetricks(verbs: Array(verbs), bottle: bottle)); verbs.removeAll()
                } label: {
                    Text("Install Selected").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(verbs.isEmpty ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(accent)))
                }.buttonStyle(.plain).disabled(verbs.isEmpty)

                Divider()

                Text("DIRECT3D BACKEND").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(p.textSecondary)

                // Quick presets that flip the three switches to the right combo.
                HStack(spacing: 6) {
                    presetButton("General / Electron", system: "app",
                                 active: !bottle.useDXVK && !bottle.useDXMT && !bottle.useD3DMetal) {
                        applyD3DPreset(dxvk: false, dxmt: false, d3dMetal: false)
                    }
                    presetButton("Modern game (D3D11)", system: "gamecontroller",
                                 active: bottle.useDXMT && !bottle.useDXVK && !bottle.useD3DMetal) {
                        applyD3DPreset(dxvk: false, dxmt: true, d3dMetal: false)
                    }
                    let isGPTK = wine.engineID == "sikarugir-gptk"
                    presetButton("D3D12 / GPTK", system: "cpu",
                                 active: bottle.useD3DMetal,
                                 disabled: !isGPTK) {
                        applyD3DPreset(dxvk: false, dxmt: false, d3dMetal: true)
                    }
                    Spacer()
                }
                Text("Tip: For Electron apps, also add ‘--disable-gpu’ in Edit Info → Launch Options.")
                    .font(.system(size: 10.5)).foregroundStyle(p.textSecondary)

                d3dToggle("Direct3D to Metal (D3DMetal)",
                          subtitle: "Apple Game Porting Toolkit — D3D11/12 → Metal. Requires the Wine GPTK engine.",
                          isOn: bottle.useD3DMetal) { on in
                    onConsole(wine.setD3DMetal(bottle: bottle, enable: on, library: library))
                }
                d3dToggle("DirectX to Metal (DXMT)",
                          subtitle: "Sikarugir DXMT — D3D11 → Metal directly. Latest build is auto-downloaded.",
                          isOn: bottle.useDXMT) { on in
                    onConsole(wine.setDXMT(bottle: bottle, enable: on, library: library))
                }
                d3dToggle("DirectX to Vulkan (DXVK)",
                          subtitle: "DXVK — D3D9/10/11 → Vulkan → MoltenVK. Best for many games.",
                          isOn: bottle.useDXVK) { on in
                    onConsole(wine.setDXVK(bottle: bottle, enable: on, library: library))
                }

                Divider()

                HStack(spacing: 8) {
                    Button(role: .destructive, action: onReset) { Label("Reset", systemImage: "arrow.counterclockwise") }
                    Button(role: .destructive, action: onDelete) { Label("Delete Bottle", systemImage: "trash") }
                    Spacer()
                }.controlSize(.small)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .task(id: bottle.id) { disk = await wine.diskUsage(bottleID: bottle.id) }
    }

    /// Pill button used for the D3D presets. Highlights when the current bottle
    /// state matches the preset; greys out when prerequisites aren't met.
    private func presetButton(_ label: String, system: String, active: Bool, disabled: Bool = false,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: active ? "checkmark.circle.fill" : system).font(.system(size: 11))
                Text(label).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(active ? Color.white : (disabled ? p.textSecondary : p.text))
            .padding(.horizontal, 10).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(active ? AnyShapeStyle(accent)
                      : AnyShapeStyle(p.control)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(active ? accent.opacity(0.8) : p.border, lineWidth: 0.5))
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain).disabled(disabled)
        .help(disabled ? "Requires the Wine GPTK engine. Open Tweaks → Change engine…" : label)
    }

    /// Apply a preset: only call setX for toggles whose target state differs from
    /// the bottle's current state. The last triggered console takes the screen;
    /// quick reg-add/delete steps finish in the background.
    private func applyD3DPreset(dxvk: Bool, dxmt: Bool, d3dMetal: Bool) {
        if bottle.useDXVK     != dxvk     { onConsole(wine.setDXVK(bottle: bottle, enable: dxvk, library: library)) }
        if bottle.useDXMT     != dxmt     { onConsole(wine.setDXMT(bottle: bottle, enable: dxmt, library: library)) }
        if bottle.useD3DMetal != d3dMetal { onConsole(wine.setD3DMetal(bottle: bottle, enable: d3dMetal, library: library)) }
    }

    /// Compact two-line toggle row: title + subtitle on the left, switch on the right.
    private func d3dToggle(_ title: String, subtitle: String, isOn: Bool, onSet: @escaping (Bool) -> Void) -> some View {
        let binding = Binding<Bool>(get: { isOn }, set: { onSet($0) })
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.text)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(p.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func info(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(p.textSecondary)
            Text(v).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text)
        }
    }

    private func toolButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) { Image(systemName: icon).font(.system(size: 11)); Text(title).font(.system(size: 12, weight: .medium)) }
                .foregroundStyle(p.text).padding(.horizontal, 10).frame(height: 28)
        }
        .buttonStyle(.plain)
        .solidSurface(RoundedRectangle(cornerRadius: 8, style: .continuous), p)
    }

    private func chooseInstaller() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows installer"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.application]
        if let exe = UTType(filenameExtension: "exe") { types.append(exe) }
        if let msi = UTType(filenameExtension: "msi") { types.append(msi) }
        panel.allowedContentTypes = types
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url {
            onConsole(wine.runInstaller(at: url, bottle: bottle))
        }
    }
}

/// Simple flow layout for the tool buttons.
private struct WrapButtons<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        // A 2-column grid is good enough and avoids a custom Layout.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
            content
        }
    }
}

// MARK: - New bottle sheet

private struct NewBottleSheet: View {
    @Environment(\.palette) private var p
    let accent: Color
    /// (label, windowsVersion, arch, installRuntimes)
    var onCreate: (String, String, String, Bool) -> Void
    var onCancel: () -> Void

    @State private var label = "New Bottle"
    @State private var winVer = "win10"
    @State private var installRuntimes = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 12) {
                Text("New Wine Bottle").font(.system(size: 15, weight: .bold)).foregroundStyle(p.text)
                TextField("Name", text: $label)
                    .textFieldStyle(.plain).font(.system(size: 13)).padding(.horizontal, 10).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(p.control))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(p.border, lineWidth: 0.5))
                HStack {
                    Text("Windows").font(.system(size: 12)).foregroundStyle(p.textSecondary)
                    Picker("", selection: $winVer) {
                        Text("7").tag("win7"); Text("10").tag("win10"); Text("11").tag("win11")
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                }
                Toggle(isOn: $installRuntimes) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Install common runtimes").font(.system(size: 12.5, weight: .semibold))
                        Text("corefonts · vcrun2019 · d3dcompiler_47 · gdiplus · xact — adds ~5 min, but most apps assume these.")
                            .font(.system(size: 10.5)).foregroundStyle(p.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.toggleStyle(.checkbox)
                Text("All bottles are 64-bit. 32-bit Windows apps run inside via WoW64 — modern Wine no longer supports pure 32-bit prefixes.")
                    .font(.system(size: 11)).foregroundStyle(p.textSecondary)
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                    Button("Create") { onCreate(label, winVer, "win64", installRuntimes) }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(18).frame(width: 460)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 16)
        }
    }
}

// MARK: - Scan importer

private struct ScanImporterSheet: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.palette) private var p
    let apps: [ScannedApp]
    let bottleID: String
    let accent: Color
    var onClose: () -> Void

    @State private var selected = Set<String>()

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                HStack {
                    Text("Found \(apps.count) apps").font(.system(size: 14, weight: .bold)).foregroundStyle(p.text)
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(p.textSecondary) }.buttonStyle(.plain)
                }.padding(16).overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }

                if apps.isEmpty {
                    Text("No installed apps found in this bottle's Program Files.")
                        .font(.system(size: 12)).foregroundStyle(p.textSecondary).padding(40)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(apps) { a in
                                Toggle(isOn: Binding(get: { selected.contains(a.path) },
                                                     set: { if $0 { selected.insert(a.path) } else { selected.remove(a.path) } })) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(a.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.text)
                                        Text(a.path.replacingOccurrences(of: ".*drive_c", with: "C:", options: .regularExpression))
                                            .font(.system(size: 10)).foregroundStyle(p.textSecondary).lineLimit(1).truncationMode(.middle)
                                    }
                                }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(12)
                    }.frame(height: 320)
                }

                HStack {
                    Spacer()
                    Button("Cancel", action: onClose)
                    Button("Import \(selected.count)") {
                        for path in selected { library.importFile(at: URL(fileURLWithPath: path), bottle: bottleID) }
                        onClose()
                    }.keyboardShortcut(.defaultAction).disabled(selected.isEmpty)
                }.padding(14).overlay(alignment: .top) { Rectangle().fill(p.separator).frame(height: 0.5) }
            }
            .frame(width: 520)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 16)
        }
    }
}
