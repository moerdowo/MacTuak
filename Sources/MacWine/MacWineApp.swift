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
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Makes the host window transparent and full-bleed so the wallpaper reaches the
/// rounded corners and Liquid Glass can sample it.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let win = v.window else { return }
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = true
            win.backgroundColor = .clear
            win.isOpaque = false
            win.styleMask.insert(.fullSizeContentView)
            win.center()
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
