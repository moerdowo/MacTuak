import SwiftUI

/// Picks a Wine engine. Used as a forced first-run onboarding step, and as a
/// reopenable sheet from Tweaks for switching the engine later.
struct EnginePickerSheet: View {
    enum Mode { case onboarding, settings }

    @Environment(\.palette) private var p
    let mode: Mode
    let accent: Color
    let selected: String
    var onChoose: (WineEngine) -> Void
    var onClose: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { if mode == .settings { onClose?() } }

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(WineEngines.catalog) { engine in
                            EngineRow(engine: engine, accent: accent,
                                      isCurrent: engine.id == selected) {
                                onChoose(engine)
                            }
                        }
                    }.padding(18)
                }
                .frame(height: 460)
                footer
            }
            .frame(width: 640)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 50, y: 24)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [accent, accent.darkened(0.3)], startPoint: .top, endPoint: .bottom))
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: "wineglass.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(mode == .onboarding ? "Choose your Wine engine" : "Switch Wine engine")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(p.text)
                Text(mode == .onboarding
                     ? "Pick the runtime MacTuak should download. You can change it later from Tweaks."
                     : "Switching downloads a new runtime (~150–230 MB) and replaces the current one. Your bottles stay.")
                    .font(.system(size: 12)).foregroundStyle(p.textSecondary)
            }
            Spacer()
            if mode == .settings, let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13)).frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.06))).foregroundStyle(p.textSecondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }
    }

    private var footer: some View {
        HStack {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(p.textSecondary)
            Text("Engines come from public projects (Gcenx, Sikarugir/Whisky). Click an engine to use it; the download happens in the background.")
                .font(.system(size: 11)).foregroundStyle(p.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) { Rectangle().fill(p.separator).frame(height: 0.5) }
    }
}

private struct EngineRow: View {
    @Environment(\.palette) private var p
    let engine: WineEngine
    let accent: Color
    let isCurrent: Bool
    var onChoose: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.85), accent.darkened(0.4)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: iconName).font(.system(size: 18, weight: .bold)).foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(engine.name).font(.system(size: 14, weight: .bold)).foregroundStyle(p.text)
                    if let badge = engine.badge {
                        Text(badge.uppercased())
                            .font(.system(size: 9, weight: .bold)).tracking(0.5)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(accent.opacity(0.18)))
                            .overlay(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 0.5))
                            .foregroundStyle(accent)
                    }
                    if isCurrent {
                        Text("CURRENT")
                            .font(.system(size: 9, weight: .bold)).tracking(0.5)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: "#28c840").opacity(0.18)))
                            .foregroundStyle(Color(hex: "#28c840"))
                    }
                    Spacer()
                    Text("≈ \(engine.approxSizeMB) MB").font(.system(size: 11)).foregroundStyle(p.textSecondary)
                }
                Text(engine.description).font(.system(size: 12)).foregroundStyle(p.textSecondary)
                HStack {
                    Spacer()
                    Button(action: onChoose) {
                        Text(isCurrent ? "Reinstall" : "Use this engine")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(LinearGradient(colors: [accent, accent.darkened(0.22)], startPoint: .top, endPoint: .bottom)))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.card)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hover ? accent.opacity(0.5) : p.border, lineWidth: hover ? 1 : 0.5))
                .shadow(color: hover ? accent.opacity(0.12) : .black.opacity(p.isDark ? 0.3 : 0.06),
                        radius: hover ? 10 : 4, y: hover ? 5 : 2)
        }
        .offset(y: hover ? -1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch engine.id {
        case "sikarugir-gptk": return "gamecontroller.fill"
        case "sikarugir-cx", "sikarugir-cx32": return "shippingbox.fill"
        case "sikarugir-whisky": return "drop.fill"
        case "sikarugir-sikarugir": return "leaf.fill"
        default: return "wineglass.fill"
        }
    }
}
