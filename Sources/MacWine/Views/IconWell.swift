import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// How the icon should resolve when a sheet is saved.
enum IconChoice {
    case keepExisting        // edit mode: leave the saved custom icon as-is
    case custom(NSImage)     // a newly chosen image
    case removed             // no custom icon → use the generated gradient tile
}

/// A 64–72pt icon well: shows the chosen/existing/custom icon (or a gradient
/// fallback), with Choose / Remove controls and image drag-and-drop.
struct IconWell<Fallback: View>: View {
    @Binding var choice: IconChoice
    var existingURL: URL?
    var accent: Color
    var size: CGFloat = 72
    @ViewBuilder var fallback: () -> Fallback

    @Environment(\.palette) private var p
    @State private var dragHover = false

    private var displayImage: NSImage? {
        switch choice {
        case .custom(let img): return img
        case .keepExisting:    return existingURL.flatMap { NSImage(contentsOf: $0) }
        case .removed:         return nil
        }
    }
    private var hasCustom: Bool {
        switch choice {
        case .custom:          return true
        case .keepExisting:    return existingURL.flatMap { NSImage(contentsOf: $0) } != nil
        case .removed:         return false
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let img = displayImage {
                    Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    fallback()
                }
            }
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(dragHover ? accent : Color.clear, lineWidth: 2))
            .onDrop(of: [.image, .fileURL], isTargeted: $dragHover) { loadDrop($0) }

            HStack(spacing: 8) {
                Button("Choose…") { choosePanel() }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(accent)
                if hasCustom {
                    Text("·").foregroundStyle(p.textSecondary)
                    Button("Remove") { choice = .removed }
                        .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(p.textSecondary)
                }
            }
        }
    }

    private func choosePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp, .icns, .image]
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            choice = .custom(img)
        }
    }

    private func loadDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                if let img = obj as? NSImage { Task { @MainActor in choice = .custom(img) } }
            }
            return true
        }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, let img = NSImage(contentsOf: url) { Task { @MainActor in choice = .custom(img) } }
            }
            return true
        }
        return false
    }
}
