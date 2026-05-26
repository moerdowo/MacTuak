import SwiftUI

// MARK: - Liquid Glass helper

extension View {
    /// Applies macOS Tahoe Liquid Glass clipped to `shape`, optionally tinted/interactive.
    func liquidGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: shape)
    }
}

// MARK: - App icon (fake .exe tile: gradient + glyph + window-pane mark)

struct AppIconView: View {
    let app: WineApp
    var size: CGFloat = 64
    var radius: CGFloat = 16

    var body: some View {
        let g1 = Color(hex: app.g1)
        let g2 = Color(hex: app.g2)
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [g1, g2], startPoint: .topLeading, endPoint: .bottomTrailing))

            // spec highlight
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.45))
                .frame(width: size * 1.2, height: size * 0.7)
                .offset(x: -size * 0.2, y: -size * 0.42)

            Text(app.glyph)
                .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)

            // windows-pane mark, bottom-right
            WindowsPane()
                .frame(width: size * 0.22, height: size * 0.22)
                .opacity(0.85)
                .padding(size * 0.08)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: g2.opacity(0.33), radius: 6, y: 4)
    }
}

private struct WindowsPane: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            let cell = s * 0.42
            let gap = s * 0.16
            ZStack {
                pane.frame(width: cell, height: cell).position(x: cell / 2, y: cell / 2)
                pane.opacity(0.65).frame(width: cell, height: cell).position(x: cell + gap + cell / 2, y: cell / 2)
                pane.opacity(0.65).frame(width: cell, height: cell).position(x: cell / 2, y: cell + gap + cell / 2)
                pane.opacity(0.85).frame(width: cell, height: cell).position(x: cell + gap + cell / 2, y: cell + gap + cell / 2)
            }
            .clipped()
        }
    }
    private var pane: some View { RoundedRectangle(cornerRadius: 1, style: .continuous).fill(.white) }
}

// MARK: - Category dot

struct CategoryDot: View {
    let category: String
    var body: some View {
        let c = Theme.categoryColors[category] ?? .gray
        Circle()
            .fill(RadialGradient(colors: [c.opacity(0.95), c], center: .init(x: 0.3, y: 0.3),
                                 startRadius: 0, endRadius: 6))
            .frame(width: 10, height: 10)
            .shadow(color: c.opacity(0.33), radius: 3)
    }
}

// MARK: - Pill button

struct PillButton<Label: View>: View {
    var primary: Bool = false
    var accent: Color
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { label() }
                .font(.system(size: 13, weight: primary ? .semibold : .medium))
                .foregroundStyle(primary ? Color.white : Color.primary)
                .frame(height: 30)
                .padding(.horizontal, 13)
        }
        .buttonStyle(.plain)
        .background {
            if primary {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [accent, accent.darkened(0.22)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                    .shadow(color: accent.opacity(0.45), radius: 5, y: 2)
            } else {
                Color.clear.liquidGlass(RoundedRectangle(cornerRadius: 10, style: .continuous), interactive: true)
            }
        }
        .brightness(hover && primary ? 0.05 : 0)
        .onHover { hover = $0 }
    }
}

// MARK: - Segmented control (Grid / List)

struct SegmentedControl<T: Hashable>: View {
    let options: [(value: T, label: String, system: String)]
    @Binding var value: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { opt in
                let active = opt.value == value
                Button { value = opt.value } label: {
                    HStack(spacing: 4) {
                        Image(systemName: opt.system).font(.system(size: 11, weight: .semibold))
                        Text(opt.label).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.background.opacity(0.95))
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .liquidGlass(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Sidebar row

struct SidebarRow<Icon: View>: View {
    @ViewBuilder var icon: () -> Icon
    let label: String
    var count: Int? = nil
    let selected: Bool
    let accent: Color
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon().frame(width: 16, alignment: .center).opacity(selected ? 1 : 0.75)
                Text(label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [accent, accent.darkened(0.2)],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: accent.opacity(0.27), radius: 2, y: 1)
                } else if hover {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .onHover { hover = $0 }
    }
}

struct SidebarSectionHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14).padding(.bottom, 6)
    }
}
