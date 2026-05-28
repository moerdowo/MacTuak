import SwiftUI

/// User-facing appearance + view preferences (the design's "Tweaks" panel),
/// persisted in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    @AppStorage("mw.accent") var accent: String = "#0a84ff" { willSet { objectWillChange.send() } }
    @AppStorage("mw.view") var view: String = "grid" { willSet { objectWillChange.send() } }
    @AppStorage("mw.dark") var dark: Bool = false { willSet { objectWillChange.send() } }
    @AppStorage("mw.sort") var sort: String = "name" { willSet { objectWillChange.send() } }   // name / recent / size / added
    @AppStorage("mw.wineChannel") var wineChannel: String = "stable" { willSet { objectWillChange.send() } } // legacy
    /// Selected Wine engine id (see WineEngines.catalog). Empty until the user
    /// picks one in the onboarding sheet.
    @AppStorage("mw.engine") var engine: String = "" { willSet { objectWillChange.send() } }
    @AppStorage("mw.engineChosen") var engineChosen: Bool = false { willSet { objectWillChange.send() } }

    var accentColor: Color { Color(hex: accent) }
    var currentEngine: WineEngine {
        WineEngines.find(engine) ?? WineEngines.defaultEngine
    }
}
