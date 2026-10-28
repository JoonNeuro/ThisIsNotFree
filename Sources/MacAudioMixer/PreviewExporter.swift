import AppKit
import SwiftUI

// Renders only this app's own views to files. No desktop or other app is captured.
@MainActor
enum PreviewExporter {
    static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "ThisIsNotFree.Preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = HubPreferences(defaults: defaults)
        preferences.appearance = "dark"
        let hub = UtilityHub(preferences: preferences, preview: true)
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        func render(_ name: String) throws {
            let controller = NSHostingController(rootView: HubView().environmentObject(hub).environmentObject(preferences))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentViewController = controller
            let view = controller.view
            view.frame = NSRect(x: 0, y: 0, width: 420, height: 640)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: directory.appendingPathComponent(name + ".png"))
            window.close()
        }
        try render("onboarding")
        preferences.setupComplete = true
        try render("dashboard")
        hub.tab = "storage"
        try render("storage")
        hub.tab = "settings"
        try render("settings")
        hub.shutdown()
    }
}
