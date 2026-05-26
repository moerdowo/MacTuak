import SwiftUI

/// User-facing appearance + view preferences (the design's "Tweaks" panel),
/// persisted in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    @AppStorage("mw.accent") var accent: String = "#0a84ff" { willSet { objectWillChange.send() } }
    @AppStorage("mw.wallpaper") var wallpaper: String = "sunset" { willSet { objectWillChange.send() } }
    @AppStorage("mw.view") var view: String = "grid" { willSet { objectWillChange.send() } }
    @AppStorage("mw.dark") var dark: Bool = false { willSet { objectWillChange.send() } }
    @AppStorage("mw.animateWallpaper") var animateWallpaper: Bool = true { willSet { objectWillChange.send() } }

    var accentColor: Color { Color(hex: accent) }
}
