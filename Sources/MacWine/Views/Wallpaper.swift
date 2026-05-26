import SwiftUI

/// Colorful Tahoe-style gradient with slowly drifting blobs. Showing through the
/// Liquid Glass panels is what makes the interface feel alive.
struct WallpaperView: View {
    let wallpaper: String
    let animate: Bool

    @State private var phase = false

    var body: some View {
        let spec = WALLPAPERS[wallpaper] ?? WALLPAPERS["sunset"]!
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: spec.base,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(Array(spec.blobs.enumerated()), id: \.offset) { idx, blob in
                    let dim = min(geo.size.width, geo.size.height)
                    let r = blob.r / 100 * dim * 1.6
                    Circle()
                        .fill(RadialGradient(colors: [blob.c, blob.c.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: r / 2))
                        .frame(width: r, height: r)
                        .opacity(blob.o)
                        .blur(radius: 2)
                        .position(x: blob.x / 100 * geo.size.width,
                                  y: blob.y / 100 * geo.size.height)
                        .offset(drift(idx))
                        .scaleEffect(phase ? scaleFor(idx) : 1)
                        .animation(animate ? .easeInOut(duration: 22 + Double(idx) * 4)
                            .repeatForever(autoreverses: true) : .default, value: phase)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { if animate { phase = true } }
        .onChange(of: animate) { _, on in phase = on }
    }

    private func drift(_ i: Int) -> CGSize {
        guard phase else { return .zero }
        switch i % 4 {
        case 0: return CGSize(width: 18, height: -22)
        case 1: return CGSize(width: -26, height: 16)
        case 2: return CGSize(width: 14, height: 22)
        default: return CGSize(width: -18, height: -26)
        }
    }
    private func scaleFor(_ i: Int) -> CGFloat {
        [1.08, 1.05, 0.95, 1.10][i % 4]
    }
}
