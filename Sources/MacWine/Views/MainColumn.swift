import SwiftUI

struct MainToolbar: View {
    @EnvironmentObject var settings: Settings
    @Environment(\.palette) private var p
    let title: String
    let subtitle: String
    @Binding var query: String
    var onAdd: () -> Void

    var body: some View {
        let accent = settings.accentColor
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 20, weight: .heavy)).tracking(-0.4).foregroundStyle(p.text)
                Text(subtitle).font(.system(size: 11.5, weight: .medium)).foregroundStyle(p.textSecondary)
            }
            Spacer(minLength: 8)

            // search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(p.textSecondary)
                TextField("Search apps", text: $query).textFieldStyle(.plain).font(.system(size: 12.5))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(p.textSecondary)
                }
            }
            .padding(.horizontal, 10).frame(width: 220, height: 30)
            .solidSurface(RoundedRectangle(cornerRadius: 10, style: .continuous), p)

            Menu {
                Picker("Sort by", selection: Binding(get: { settings.sort }, set: { settings.sort = $0 })) {
                    Text("Name").tag("name")
                    Text("Last run").tag("recent")
                    Text("Size").tag("size")
                    Text("Recently added").tag("added")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 13, weight: .medium)).foregroundStyle(p.text)
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .background(p.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.border, lineWidth: 0.5))

            SegmentedControl(options: [
                (value: "grid", label: "Grid", system: "square.grid.2x2"),
                (value: "list", label: "List", system: "list.bullet"),
            ], value: Binding(get: { settings.view }, set: { settings.view = $0 }))

            TweaksButton()

            PillButton(primary: true, accent: accent, action: onAdd) {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                Text("Add App")
            }
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }
    }
}

struct ListHeaderRow: View {
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: 36)
            cell("Name", 220); cell("Category", 100); cell("Arch / Size", 90)
            cell("Last run", nil)
            Color.clear.frame(width: 80)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(p.isDark ? Color.black.opacity(0.15) : Color.black.opacity(0.03))
        .overlay(alignment: .bottom) { Rectangle().fill(p.separator).frame(height: 0.5) }
    }
    private func cell(_ t: String, _ w: CGFloat?) -> some View {
        Text(t.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(0.4)
            .foregroundStyle(p.textSecondary)
            .frame(width: w, alignment: .leading)
            .frame(maxWidth: w == nil ? .infinity : nil, alignment: .leading)
    }
}

struct EmptyStateView: View {
    @Environment(\.palette) private var p
    let accent: Color
    let hasQuery: Bool
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [accent, accent.darkened(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 80, height: 80)
                .overlay(Image(systemName: hasQuery ? "magnifyingglass" : "square.and.arrow.up")
                    .font(.system(size: 32, weight: .medium)).foregroundStyle(.white))
                .shadow(color: accent.opacity(0.4), radius: 24, y: 8)
            Text(hasQuery ? "No matches" : "No apps here yet").font(.system(size: 17, weight: .bold)).foregroundStyle(p.text)
            Text(hasQuery ? "Try a different search term, or remove the filter."
                          : "Drop a .exe or folder anywhere in the window — or click below to pick from your Mac.")
                .font(.system(size: 13)).foregroundStyle(p.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
            if !hasQuery {
                PillButton(primary: true, accent: accent, action: onAdd) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                    Text("Add Application")
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 80).padding(.horizontal, 24)
    }
}

struct StatusBar: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var wine: WineManager
    @Environment(\.palette) private var p

    var body: some View {
        let running = library.runningCount
        let totalBytes = library.apps.reduce(Int64(0)) { $0 + $1.sizeBytes }
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                if wine.runtime.isBusy { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12) }
                else { Image(systemName: "wineglass") }
                Text(wine.runtime.statusText)
            }
            .foregroundStyle(wine.runtime.isWarning ? Color(hex: "#ff9f0a") : p.textSecondary)
            divider
            Label("\(library.bottles.count) bottles · \(WineApp.humanSize(totalBytes))", systemImage: "internaldrive")
                .foregroundStyle(p.textSecondary)
            divider
            HStack(spacing: 6) {
                Circle().fill(running > 0 ? Color(hex: "#28c840") : p.textSecondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .shadow(color: running > 0 ? Color(hex: "#28c840").opacity(0.6) : .clear, radius: 4)
                Text(running > 0 ? "\(running) running" : "Idle")
            }
            .foregroundStyle(p.textSecondary)
            Spacer()
            Text("\(library.apps.count) apps in library").foregroundStyle(p.textSecondary)
        }
        .font(.system(size: 11.5, weight: .medium))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 18).frame(height: 32)
        .background(p.bar)
        .overlay(alignment: .top) { Rectangle().fill(p.separator).frame(height: 0.5) }
    }

    private var divider: some View {
        Rectangle().fill(p.border).frame(width: 1, height: 14)
    }
}
