import SwiftUI
import AppKit

struct DiagnosticSheet: View {
    @EnvironmentObject var wine: WineManager
    @EnvironmentObject var library: LibraryStore
    @Environment(\.palette) private var p
    let accent: Color
    var onClose: () -> Void

    @State private var items: [Diagnostic.Item] = []
    @State private var running = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "stethoscope").foregroundStyle(accent)
                    Text("Diagnostic").font(.system(size: 15, weight: .bold)).foregroundStyle(p.text)
                    Spacer()
                    Button {
                        let txt = Diagnostic.formatted(items)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(txt, forType: .string)
                    } label: {
                        Label("Copy report", systemImage: "doc.on.clipboard").font(.system(size: 11.5, weight: .semibold))
                    }.buttonStyle(.plain).foregroundStyle(accent)
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13)).frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.06))).foregroundStyle(p.textSecondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }

                if running {
                    VStack(spacing: 10) {
                        Spacer(); ProgressView()
                        Text("Running checks…").font(.system(size: 12)).foregroundStyle(p.textSecondary); Spacer()
                    }.frame(height: 420)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(items) { item in row(item) }
                        }.padding(14)
                    }.frame(height: 420)
                }
            }
            .frame(width: 620)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 24)
        }
        .task { items = await Diagnostic.run(wine: wine, library: library); running = false }
    }

    private func row(_ item: Diagnostic.Item) -> some View {
        HStack(alignment: .top, spacing: 10) {
            badge(item.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.text)
                Text(item.detail).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(p.textSecondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(p.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.border, lineWidth: 0.5))
    }

    private func badge(_ s: Diagnostic.Item.Status) -> some View {
        let (label, color): (String, Color) = {
            switch s {
            case .ok:   return ("OK",   Color(hex: "#28c840"))
            case .warn: return ("WARN", Color(hex: "#ffcc00"))
            case .fail: return ("FAIL", Color(hex: "#ff453a"))
            case .info: return ("INFO", Color(hex: "#5BA4F0"))
            }
        }()
        return Text(label).font(.system(size: 9, weight: .bold)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .frame(width: 44)
    }
}
