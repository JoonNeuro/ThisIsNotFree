import AppKit
import SwiftUI

// Renders only this app's own views to files. No desktop or other app is captured.
@MainActor
enum PreviewExporter {
    static func export(to directory: URL, live: Bool = false) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "ThisIsNotFree.Preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = HubPreferences(defaults: defaults)
        preferences.appearance = "dark"
        let hub = UtilityHub(preferences: preferences, preview: !live)
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        func render<V: View>(_ name: String, view: V, width: CGFloat = 1280, height: CGFloat = 820) throws {
            let controller = NSHostingController(rootView: view.environmentObject(hub).environmentObject(preferences))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentViewController = controller
            let view = controller.view
            view.frame = NSRect(x: 0, y: 0, width: width, height: height)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: directory.appendingPathComponent(name + ".png"))
            window.close()
        }
        if live {
            let reader = UUID()
            for module in [UtilityModule.system, .audio, .storage] { hub.acquirePreview(module, reader: reader) }
            try await Task.sleep(for: .milliseconds(2300))
            try render("live-catalog", view: WorkspaceView())
            hub.tab = "storage"
            try render("live-storage", view: WorkspaceView())
            hub.shutdown()
            return
        }
        try render("onboarding", view: WorkspaceView())
        preferences.modules = ["system", "audio", "storage"]
        preferences.setupComplete = true
        preferences.workspaceConfigured = true
        try render("dashboard", view: WorkspaceView())
        hub.tab = "awake"
        try render("tool-preview", view: WorkspaceView())
        hub.tab = "layout"
        try render("layout", view: WorkspaceView())
        hub.tab = "storage"
        try render("storage", view: WorkspaceView())
        try render("box", view: BoxPopoverView(shelf: hub.shelf), width: 420, height: 580)
        try render("menu-bar-icon", view:
            HStack(spacing: 0) {
                Image(nsImage: BrandIcon.menuBar).renderingMode(.template).foregroundStyle(.black)
                    .frame(width: 210, height: 100).background(Color.white)
                Image(nsImage: BrandIcon.menuBar).renderingMode(.template).foregroundStyle(.white)
                    .frame(width: 210, height: 100).background(Color.black)
            }, width: 420, height: 100)
        try render("icons", view: IconSettingsView(icons: hub.icons).padding(24)
            .frame(width: 640, height: 440, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)), width: 640, height: 440)
        hub.tab = "settings"
        try render("settings", view: WorkspaceView())
        hub.shutdown()
    }
}
