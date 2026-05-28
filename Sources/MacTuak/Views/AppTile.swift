import SwiftUI

struct AppTile: View {
    let app: WineApp
    let accent: Color
    var onLaunch: () -> Void
    var onToggleFav: () -> Void
    var menu: () -> AnyView

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                AppIconView(app: app, size: 72, radius: 18)
                if app.running {
                    Circle().fill(Color(hex: "#28c840"))
                        .frame(width: 22, height: 22)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(.white))
                        .overlay(Circle().strokeBorder(.white.opacity(0.95), lineWidth: 2.5))
                        .shadow(color: Color(hex: "#28c840").opacity(0.55), radius: 6)
                        .offset(x: 5, y: 5)
                }
            }
            Text(app.name)
                .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                .foregroundStyle(p.text)
            HStack(spacing: 5) {
                Text(app.arch)
                Text("·").opacity(0.4)
                Text(app.sizeDisplay)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(p.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(p.card)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(hover ? accent.opacity(0.5) : p.border, lineWidth: hover ? 1 : 0.5))
                .shadow(color: hover ? accent.opacity(0.18) : .black.opacity(p.isDark ? 0.3 : 0.10),
                        radius: hover ? 14 : 7, y: hover ? 8 : 4)
        }
        .overlay(alignment: .topLeading) {
            if hover || app.favorite {
                Button(action: onToggleFav) {
                    Image(systemName: app.favorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(app.favorite ? Color(hex: "#ffcc00") : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hover {
                Menu { menu() } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13))
                        .foregroundStyle(p.text)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(p.control).overlay(Circle().strokeBorder(p.border, lineWidth: 0.5)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(hover ? 1.0 : 1.0)
        .offset(y: hover ? -2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        .onHover { hover = $0 }
        .onTapGesture(count: 2, perform: onLaunch)
        .contextMenu { menu() }
    }
}

struct AppListRow: View {
    let app: WineApp
    let accent: Color
    let isLast: Bool
    var onLaunch: () -> Void
    var menu: () -> AnyView

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(app: app, size: 36, radius: 9)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).foregroundStyle(p.text)
                    if app.running {
                        Circle().fill(Color(hex: "#28c840")).frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                    }
                }
                Text(app.publisher).font(.system(size: 11.5, weight: .medium)).foregroundStyle(p.textSecondary)
            }
            .frame(width: 220, alignment: .leading)

            Text(app.category).font(.system(size: 12)).foregroundStyle(p.textSecondary).frame(width: 100, alignment: .leading)
            Text("\(app.arch) · \(app.sizeDisplay)").font(.system(size: 12)).foregroundStyle(p.textSecondary).frame(width: 90, alignment: .leading)
            Text(app.lastRunDisplay).font(.system(size: 12)).foregroundStyle(p.textSecondary).frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Button(action: onLaunch) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text("Run").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [accent, accent.darkened(0.22)], startPoint: .top, endPoint: .bottom)))
                }
                .buttonStyle(.plain)
                Menu { menu() } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(p.text)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.control)
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(p.border, lineWidth: 0.5)))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .opacity(hover ? 1 : 0)
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(hover ? (p.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)) : .clear)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(p.separator).frame(height: 0.5) }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2, perform: onLaunch)
        .contextMenu { menu() }
    }
}
