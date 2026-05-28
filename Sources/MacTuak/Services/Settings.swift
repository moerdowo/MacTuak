import SwiftUI

/// User-facing appearance + view preferences (the design's "Tweaks" panel),
/// persisted in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    @AppStorage("mw.accent") var accent: String = "#0a84ff" { willSet { objectWillChange.send() } }
    @AppStorage("mw.view") var view: String = "grid" { willSet { objectWillChange.send() } }
    @AppStorage("mw.dark") var dark: Bool = false { willSet { objectWillChange.send() } }
    @AppStorage("mw.sort") var sort: String = "name" { willSet { objectWillChange.send() } }   // name / recent / size / added
    @AppStorage("mw.wineChannel") var wineChannel: String = "stable" { willSet { objectWillChange.send() } } // stable / staging / devel

    var accentColor: Color { Color(hex: accent) }
}
