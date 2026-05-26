import SwiftUI

/// About / Licenses & Acknowledgements — fulfills the open-source attribution
/// and source-offer requirements (primarily Wine's LGPL-2.1).
struct LicensesSheet: View {
    @EnvironmentObject var wine: WineManager
    @Environment(\.palette) private var p
    let accent: Color
    var onClose: () -> Void

    @State private var viewing: (title: String, text: String)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text").foregroundStyle(accent)
                    Text("About & Licenses").font(.system(size: 15, weight: .bold)).foregroundStyle(p.text)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13)).frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.06))).foregroundStyle(p.textSecondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("MacWine runs Windows applications using Wine and related open-source software. The notices below fulfill those components' license requirements.")
                            .font(.system(size: 12)).foregroundStyle(p.textSecondary)

                        section("Wine") {
                            kv("License", "GNU LGPL v2.1 or later")
                            kv("Copyright", "© 1993–2026 the Wine project authors")
                            kv("Installed", wine.runtime.version.isEmpty ? "—" : "\(wine.runtime.version) (\(wine.channel))")
                            HStack(spacing: 8) {
                                docButton("License (LGPL 2.1)", file: "Wine-COPYING.LIB")
                                docButton("Notice", file: "Wine-LICENSE")
                                docButton("Authors", file: "Wine-AUTHORS")
                            }
                            HStack(spacing: 14) {
                                Link("Source code", destination: URL(string: "https://gitlab.winehq.org/wine/wine")!)
                                Link("Release sources", destination: URL(string: "https://dl.winehq.org/wine/source/")!)
                            }.font(.system(size: 12, weight: .semibold)).tint(accent)
                            Text("The Wine binary is used unmodified as a separate, user-replaceable runtime.")
                                .font(.system(size: 11)).foregroundStyle(p.textSecondary)
                        }

                        section("Runtime build") {
                            Text("macOS Wine builds are produced by the Gcenx project and may bundle MoltenVK (Apache-2.0), DXVK (zlib), VKD3D, FAudio (zlib), Wine-Mono (MIT) and Wine-Gecko (MPL-2.0).")
                                .font(.system(size: 12)).foregroundStyle(p.text)
                            Link("github.com/Gcenx/macOS_Wine_builds", destination: URL(string: "https://github.com/Gcenx/macOS_Wine_builds")!)
                                .font(.system(size: 12, weight: .semibold)).tint(accent)
                        }

                        section("winetricks") {
                            Text("Optional components are installed via winetricks (LGPL-2.1), downloaded at runtime. Microsoft redistributables it fetches are under Microsoft's own EULAs and are not bundled by MacWine.")
                                .font(.system(size: 12)).foregroundStyle(p.text)
                            HStack(spacing: 14) {
                                docButton("Third-party notices", file: "THIRD-PARTY")
                                Link("winetricks", destination: URL(string: "https://github.com/Winetricks/winetricks")!)
                                    .font(.system(size: 12, weight: .semibold)).tint(accent)
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(width: 540, height: 420)
            }
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 24)

            if let viewing {
                TextFileViewer(title: viewing.title, text: viewing.text) { self.viewing = nil }.zIndex(10)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(p.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k).font(.system(size: 12)).foregroundStyle(p.textSecondary).frame(width: 80, alignment: .leading)
            Text(v).font(.system(size: 12, weight: .medium)).foregroundStyle(p.text)
        }
    }

    private func docButton(_ label: String, file: String) -> some View {
        Button {
            viewing = (label, loadLicense(file))
        } label: {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
        }.buttonStyle(.plain)
    }

    private func loadLicense(_ name: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "licenses"),
           let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let url = Bundle.main.url(forResource: name, withExtension: "txt"),
           let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        return "This document is included with the app distribution under:\nContents/Resources/licenses/\(name).txt"
    }
}

private struct TextFileViewer: View {
    @Environment(\.palette) private var p
    let title: String
    let text: String
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(p.text)
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(p.textSecondary) }.buttonStyle(.plain)
                }.padding(14).overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }
                ScrollView {
                    Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.text)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }.frame(width: 560, height: 420)
            }
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
        }
    }
}
