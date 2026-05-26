import SwiftUI

/// First-run overlay shown while the bundled Wine runtime downloads/installs.
struct OnboardingOverlay: View {
    @EnvironmentObject var wine: WineManager
    @Environment(\.palette) private var p
    let accent: Color
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 16) {
                if let img = NSImage(named: NSImage.applicationIconName) ?? Bundle.main.image(forResource: "AppIcon") {
                    Image(nsImage: img).resizable().frame(width: 88, height: 88)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [accent, accent.darkened(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 88, height: 88)
                        .overlay(Image(systemName: "wineglass.fill").font(.system(size: 40)).foregroundStyle(.white))
                }

                Text("Setting up MacWine").font(.system(size: 18, weight: .bold)).foregroundStyle(p.text)
                Text("Downloading the latest stable Wine runtime so you can run Windows apps. This happens once.")
                    .font(.system(size: 13)).foregroundStyle(p.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)

                if wine.runtime.kind == .downloading {
                    ProgressView(value: wine.runtime.progress)
                        .progressViewStyle(.linear).frame(width: 320).tint(accent)
                } else {
                    ProgressView().frame(width: 320)
                }
                Text(wine.runtime.statusText).font(.system(size: 11.5, weight: .medium)).foregroundStyle(p.textSecondary)

                Button("Continue in the background", action: onContinue)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(accent)
                    .padding(.top, 4)
            }
            .padding(36).frame(width: 460)
            .background(p.appBG, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 50, y: 24)
        }
    }
}
