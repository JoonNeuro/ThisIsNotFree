import AppKit
import SwiftUI

@MainActor
final class ShelfBarController {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var anchorWindow: NSWindow?
    var isShown: Bool { panel?.isVisible == true }
    func show(button: NSStatusBarButton, hub: UtilityHub, preferences: HubPreferences, includeTools: Bool,
              openTool: @escaping (UtilityModule) -> Void) {
        close()
        guard let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let width = min(ShelfBarMetrics.width, screen.frame.width - 24)
        let height = ShelfBarMetrics.height
        let menuHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let x = min(max(anchor.midX-width/2, screen.frame.minX+12), screen.frame.maxX-width-12)
        let y = screen.frame.maxY-menuHeight-height-2
        let panel = NSPanel(contentRect: .init(x: x, y: y, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.title = "Menu Bar Shelf"
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView:
            ShelfPopupView(shelf: hub.shelf, width: width, includeTools: includeTools, openTool: openTool)
                .environmentObject(hub).environmentObject(preferences)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12))))
        self.panel = panel
        anchorWindow = window
        panel.orderFrontRegardless()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consume = MainActor.assumeIsolated {
                if event.type == .keyDown && event.keyCode == 53 { self?.close(); return true }
                if event.type != .keyDown, event.window !== self?.panel, event.window !== self?.anchorWindow { self?.close() }
                return false
            }
            return consume ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }
    func close() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        panel?.orderOut(nil); panel?.close(); panel = nil
        anchorWindow = nil
    }
}
