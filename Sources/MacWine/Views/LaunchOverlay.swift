import SwiftUI

struct LaunchOverlay: View {
    @ObservedObject var session: LaunchSession
    let accent: Color
    var onClose: () -> Void

    private var badge: (String, Color) {
        switch session.phase {
        case .booting:  return ("Booting", Color(hex: "#ffd86b"))
        case .running:  return ("Running", Color(hex: "#5eea85"))
        case .exited:   return ("Exited", .secondary)
        case .error:    return ("Failed", Color(hex: "#ff6b6b"))
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                // header
                HStack(spacing: 14) {
                    AppIconView(app: session.app, size: 56, radius: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(session.app.name).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            Text(badge.0.uppercased())
                                .font(.system(size: 10, weight: .semibold)).tracking(0.4)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(badge.1.opacity(0.22)))
                                .overlay(Capsule().strokeBorder(badge.1.opacity(0.35), lineWidth: 0.5))
                                .foregroundStyle(badge.1)
                        }
                        Text("Bottle \(session.app.bottle) · \(session.app.arch)")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
                            .foregroundStyle(.white.opacity(0.7))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5) }

                // terminal
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(session.lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(color(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 18)
                    }
                    .frame(maxHeight: 280)
                    .onChange(of: session.lines.count) { _, _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }

                // footer
                HStack {
                    Text(footerText).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Button(action: onClose) {
                        Text(session.phase == .running ? "Hide" : "Close")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.1)))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.black.opacity(0.18))
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5) }
            }
            .frame(width: 540)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#1c1c24").opacity(0.82))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.55), radius: 40, y: 24)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    private var footerText: String {
        switch session.phase {
        case .running: return "Window opened — switch to the running app."
        case .booting: return "Initializing Wine prefix and DLLs…"
        case .exited:  return "Process finished."
        case .error:   return "Wine could not start this application."
        }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("→") { return Color(hex: "#5eea85") }
        if line.hasPrefix("error") { return Color(hex: "#ff8a8a") }
        if line.hasPrefix("fixme") || line.contains("fixme:") { return .white.opacity(0.4) }
        if line.hasPrefix("$") { return .white }
        return .white.opacity(0.78)
    }
}
