import AppKit
import ApplicationServices

struct ShelfItem: Identifiable {
    let id: String
    let title: String
    let appName: String
    let icon: NSImage?
    let element: AXUIElement
    var frame: CGRect? = nil
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
    @Published private(set) var arrangement = ShelfArrangement.load()
    @Published private(set) var liveIcons: [String: NSImage] = [:]
    @Published private(set) var capturedAt: Date?
    @Published private(set) var screenCaptureGranted = CGPreflightScreenCaptureAccess()
    @Published private(set) var capturing = false
    @Published private(set) var arranging = false
    @Published private(set) var appliedItems: Set<String> = []
    var beforeActivation: (() -> Void)?
    let supportsCollapse = ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27
    private var divider: NSStatusItem?
    private let queue = DispatchQueue(label: "ThisIsNotFree.accessibility", qos: .userInitiated)
    private var refreshCompletions: [() -> Void] = []

    var pinnedItems: [ShelfItem] {
        pinned.compactMap { id in items.first(where: { $0.id == id }) }
    }
    var shelfItems: [ShelfItem] { arrangement.ordered(items.filter { arrangement.destination($0.id) == .shelf }) }
    func assign(_ id: String, to destination: ShelfDestination, before: String? = nil) {
        arrangement.order = arrangement.ordered(items).map(\.id)
        arrangement.assign(id, to: destination, before: before)
        arrangement.save()
        appliedItems.remove(id)
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
                                           appName: appName, icon: icon, element: element, frame: Self.elementFrame(element)))
                }
            }
            let unique = found.reduce(into: [ShelfItem]()) { result, item in
                if !result.contains(where: { $0.id == item.id }) { result.append(item) }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.items = unique; self.refreshing = false
                if self.screenCaptureGranted { self.captureIcons() }
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

extension MenuShelf {
    nonisolated static func elementFrame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              origin.x.isFinite, origin.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
    func requestIconCapture() {
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
        if !screenCaptureGranted { screenCaptureGranted = CGRequestScreenCaptureAccess() }
        if screenCaptureGranted { refresh { [weak self] in self?.captureIcons() } }
        else {
            message = "Allow Screen Recording for original icon snapshots, then refresh. Without it, only labeled app-icon fallbacks are shown."
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
    func captureIcons() {
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
        guard screenCaptureGranted, !capturing else { return }
        capturing = true
        let visibleItems = items
        Task { [weak self] in
            guard let self else { return }
            defer { self.capturing = false }
            do {
                let images = try await ShelfIconCapture.capture(visibleItems)
                // Hidden originals cannot be captured; keep their last known image.
                self.liveIcons.merge(images) { _, new in new }
                self.capturedAt = images.isEmpty ? self.capturedAt : Date()
            } catch { self.message = "Icon snapshots could not be read: \(error.localizedDescription)" }
        }
    }

    func applyArrangement() {
        guard supportsCollapse else { message = "This macOS version does not support section collapsing. Choices affect Shelf contents only."; return }
        guard AXIsProcessTrusted() else { requestAccessibility(); return }
        guard !arranging else { return }
        // Explicit user action: reveal first, then Command-drag originals using
        // the OS's normal menu bar rearrangement gesture. Verify every move.
        enableOrganizer(true); setCollapsed(false)
        beforeActivation?()
        arranging = true; appliedItems = []
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            let desired = self.arrangement.ordered(self.items)
            var failed: [String] = []
            for item in desired {
                guard let button = self.divider?.button, let window = button.window,
                      let main = NSScreen.screens.first else { failed.append(item.title); continue }
                let cocoa = window.convertToScreen(button.convert(button.bounds, to: nil))
                let top = main.frame.maxY
                let dividerRect = CGRect(x: cocoa.minX, y: top-cocoa.maxY, width: cocoa.width, height: cocoa.height)
                guard let source = Self.elementFrame(item.element), source.width > 0, source.height > 0,
                      abs(source.midY-dividerRect.midY) < 12 else { failed.append(item.title); continue }
                let keep = self.arrangement.destination(item.id) == .keep
                let alreadyPlaced = keep ? source.midX > dividerRect.maxX : source.midX < dividerRect.minX
                if alreadyPlaced { self.appliedItems.insert(item.id); continue }
                // Stay within the menu bar. Never drag down into the removal area.
                let target = CGPoint(x: keep ? dividerRect.maxX + 12 : dividerRect.minX - 12, y: source.midY)
                let start = CGPoint(x: source.midX, y: source.midY)
                await Self.commandDrag(from: start, to: target)
                try? await Task.sleep(for: .milliseconds(200))
                guard let moved = Self.elementFrame(item.element), let currentWindow = button.window else { failed.append(item.title); continue }
                let newDivider = currentWindow.convertToScreen(button.convert(button.bounds, to: nil))
                let success = keep ? moved.midX > newDivider.maxX : moved.midX < newDivider.minX
                if success { self.appliedItems.insert(item.id) } else { failed.append(item.title) }
            }
            self.arranging = false
            // Failed items remain revealed. Do not report a planned assignment as
            // a successful hide or collapse any unverified arrangement.
            if failed.isEmpty { self.setCollapsed(true); self.message = "Arrangement applied. Shelf and Hidden originals are collapsed; kept icons remain visible." }
            else { self.message = "Kept originals revealed. Could not move: \(failed.joined(separator: ", ")). Command-drag these beside the divider, then apply again." }
            self.refresh()
        }
    }
    nonisolated private static func commandDrag(from start: CGPoint, to end: CGPoint) async {
        guard CGPreflightPostEventAccess(), let source = CGEventSource(stateID: .hidSystemState) else { return }
        let original = CGEvent(source: nil)?.location
        func post(_ kind: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: kind, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand; event?.post(tap: .cghidEventTap)
        }
        post(.leftMouseDown, start)
        for step in 1...16 {
            try? await Task.sleep(for: .milliseconds(18))
            let t = CGFloat(step)/16
            post(.leftMouseDragged, .init(x: start.x+(end.x-start.x)*t, y: start.y+(end.y-start.y)*t))
        }
        post(.leftMouseUp, end)
        if let original { CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: original, mouseButton: .left)?.post(tap: .cghidEventTap) }
    }
}
