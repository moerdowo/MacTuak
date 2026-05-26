import SwiftUI

/// A dark terminal overlay for bottle tasks (wineboot, winetricks, …).
struct ConsoleSheet: View {
    @ObservedObject var session: ConsoleSession
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { if session.phase != .running && session.phase != .booting { onClose() } }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if session.phase == .running || session.phase == .booting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: session.phase == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(session.phase == .error ? Color(hex: "#ff8a8a") : Color(hex: "#5eea85"))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        Text(session.subtitle).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
                            .foregroundStyle(.white.opacity(0.7))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5) }

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
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)
                    }
                    .frame(width: 580, height: 320)
                    .onChange(of: session.lines.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: "#1c1c24").opacity(0.96)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.55), radius: 40, y: 24)
        }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("→") { return Color(hex: "#5eea85") }
        if line.lowercased().contains("error") || line.lowercased().contains("failed") { return Color(hex: "#ff8a8a") }
        if line.hasPrefix("$") { return .white }
        return .white.opacity(0.78)
    }
}
