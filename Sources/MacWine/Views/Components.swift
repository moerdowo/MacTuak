import SwiftUI

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

            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.45))
                .frame(width: size * 1.2, height: size * 0.7)
                .offset(x: -size * 0.2, y: -size * 0.42)

            Text(app.glyph)
                .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)

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

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { label() }
                .font(.system(size: 13, weight: primary ? .semibold : .medium))
                .foregroundStyle(primary ? Color.white : p.text)
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
                    .shadow(color: accent.opacity(0.35), radius: 4, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hover ? p.controlActive : p.control)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
            }
        }
        .onHover { hover = $0 }
    }
}

// MARK: - Segmented control (Grid / List)

struct SegmentedControl<T: Hashable>: View {
    let options: [(value: T, label: String, system: String)]
    @Binding var value: T
    @Environment(\.palette) private var p

    var body: some View {
        let track = p.isDark ? p.control : Color.black.opacity(0.06)
        let thumb = p.isDark ? p.controlActive : Color.white
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { opt in
                let active = opt.value == value
                Button { value = opt.value } label: {
                    HStack(spacing: 4) {
                        Image(systemName: opt.system).font(.system(size: 11, weight: .semibold))
                        Text(opt.label).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(active ? p.text : p.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(thumb)
                                .shadow(color: .black.opacity(p.isDark ? 0.3 : 0.12), radius: 2, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(track))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))
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

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon().frame(width: 16, alignment: .center).opacity(selected ? 1 : 0.75)
                Text(label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? .white.opacity(0.85) : p.textSecondary)
                }
            }
            .foregroundStyle(selected ? Color.white : p.text)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [accent, accent.darkened(0.2)],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: accent.opacity(0.27), radius: 2, y: 1)
                } else if hover {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(p.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .onHover { hover = $0 }
    }
}

struct SidebarSectionHeader: View {
    let text: String
    @Environment(\.palette) private var p
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(p.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14).padding(.bottom, 6)
    }
}
