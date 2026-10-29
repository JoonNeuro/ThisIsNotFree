import AppKit
import ApplicationServices

struct ShelfItem: Identifiable {
    let id: String
    let title: String
    let appName: String
    let icon: NSImage?
    let element: AXUIElement
}

@MainActor
final class MenuShelf: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var refreshing = false
    @Published private(set) var message: String?
    @Published private(set) var pinned: [String] = UserDefaults.standard.stringArray(forKey: "shelf.pinned") ?? []
    @Published private(set) var collapsed = false
    @Published private(set) var organizerEnabled = false
    var beforeActivation: (() -> Void)?
    let supportsCollapse = ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27
    private var divider: NSStatusItem?
    private let queue = DispatchQueue(label: "ThisIsNotFree.accessibility", qos: .userInitiated)
    private var refreshCompletions: [() -> Void] = []

    var pinnedItems: [ShelfItem] {
        pinned.compactMap { id in items.first(where: { $0.id == id }) }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityGranted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    func refresh(completion: (() -> Void)? = nil) {
        accessibilityGranted = AXIsProcessTrusted()
        guard accessibilityGranted else { completion?(); return }
        if let completion { refreshCompletions.append(completion) }
        guard !refreshing else { return }
        refreshing = true
        let apps = NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .map { ($0.processIdentifier, $0.bundleIdentifier ?? "pid:\($0.processIdentifier)", $0.localizedName ?? "Application", $0.icon) }
        queue.async { [weak self] in
            var found: [ShelfItem] = []
            for (pid, bundle, appName, icon) in apps {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.15)
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &value) == .success,
                      let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
                let bar = value as! AXUIElement
                var children: CFTypeRef?
                guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &children) == .success,
                      let elements = children as? [AXUIElement] else { continue }
                for (index, element) in elements.enumerated() {
                    func text(_ attribute: String) -> String? {
                        var value: CFTypeRef?
                        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
                        return (value as? String).flatMap { $0.isEmpty ? nil : $0 }
                    }
                    let title = text(kAXDescriptionAttribute) ?? text(kAXTitleAttribute) ?? appName
                    let identifier = text(kAXIdentifierAttribute) ?? "item:\(index)"
                    found.append(ShelfItem(id: "\(bundle):\(identifier)", title: title,
                                           appName: appName, icon: icon, element: element))
                }
            }
            let unique = found.reduce(into: [ShelfItem]()) { result, item in
                if !result.contains(where: { $0.id == item.id }) { result.append(item) }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.items = unique; self.refreshing = false
                let completions = self.refreshCompletions; self.refreshCompletions = []
                completions.forEach { $0() }
            }
        }
    }

    func openSystemMenu(_ kind: NotchZone, preferredID: String? = nil) {
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            message = "Allow Accessibility, then click the edge again to open the original system menu."
            return
        }
        refresh { [weak self] in
            guard let self else { return }
            let match = preferredID.flatMap { id in self.items.first { $0.id == id } } ?? self.items.first { item in
                guard item.id.hasPrefix("com.apple.controlcenter:") || item.id.hasPrefix("com.apple.systemuiserver:") else { return false }
                let key = (item.id + " " + item.title).lowercased().filter { $0.isLetter || $0.isNumber }
                return kind.menuKeys.contains { key.contains($0) }
            }
            if let match { self.activate(match) }
            else { self.message = "The original \(kind.title) menu is not exposed. Show its icon in macOS Menu Bar settings, or select its menu item in Notch Hub. No replacement menu was opened." }
        }
    }

    func togglePin(_ item: ShelfItem) {
        if pinned.contains(item.id) { pinned.removeAll { $0 == item.id } } else { pinned.append(item.id) }
        UserDefaults.standard.set(pinned, forKey: "shelf.pinned")
    }

    func removeUnavailablePins() {
        pinned = pinned.filter { id in items.contains(where: { $0.id == id }) }
        UserDefaults.standard.set(pinned, forKey: "shelf.pinned")
    }

    func activate(_ item: ShelfItem) {
        setCollapsed(false)
        beforeActivation?()
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            AXUIElementSetMessagingTimeout(item.element, 0.5)
            let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
            Task { @MainActor [weak self] in
                self?.message = result == .success ? nil : "This item could not be opened. Refresh the shelf or use its original menu bar icon."
            }
        }
    }

    func enableOrganizer(_ enabled: Bool) {
        organizerEnabled = enabled && supportsCollapse
        UserDefaults.standard.set(organizerEnabled, forKey: "shelf.organizerEnabled")
        if organizerEnabled && divider == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "ThisIsNotFree.Divider"
            item.button?.title = "│"
            item.button?.alignment = .right
            item.button?.toolTip = "Command-drag icons to the left of this divider to collapse them."
            divider = item
        } else if !organizerEnabled, let divider {
            setCollapsed(false)
            NSStatusBar.system.removeStatusItem(divider)
            self.divider = nil
        }
    }

    func restoreOrganizerPreference() {
        if !organizerEnabled && UserDefaults.standard.bool(forKey: "shelf.organizerEnabled") { enableOrganizer(true) }
    }

    func setCollapsed(_ value: Bool) {
        guard organizerEnabled, supportsCollapse else { collapsed = false; return }
        collapsed = value
        divider?.length = value ? 10_000 : NSStatusItem.squareLength
    }

    func restore() { setCollapsed(false); enableOrganizer(false) }
    func shutdown() {
        setCollapsed(false)
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        divider = nil
        organizerEnabled = false
    }
}
