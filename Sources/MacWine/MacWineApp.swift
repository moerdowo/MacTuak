import SwiftUI
import AppKit

@main
struct MacWineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @StateObject private var settings = Settings()
    @StateObject private var library = LibraryStore()
    @StateObject private var wine = WineManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(wine)
                .frame(minWidth: 940, minHeight: 620)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 820)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Notifier.requestAuthorization()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Full-bleed opaque window: hidden/transparent titlebar so the content runs to
/// the top (traffic lights float over the sidebar), but the window itself stays
/// opaque — no see-through background.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let win = v.window else { return }
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = true
            win.styleMask.insert(.fullSizeContentView)
            win.center()
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
