import AppKit
import SwiftUI
import Combine
import UserNotifications

@main
struct MacAudioMixerApp: App {
    @NSApplicationDelegateAdaptor(MixerAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class MixerAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private weak var appliedAppIcon: NSImage?
    private var mainWindow: NSWindow?
    private var moduleItems: [UtilityModule: NSStatusItem] = [:]
    private let toolPopover = NSPopover()
    private let shelfBar = ShelfBarController()
    private var currentTool: UtilityModule?
    private var cpuItem: NSStatusItem?
    private var gpuItem: NSStatusItem?
    private var groupItems: [UUID: NSStatusItem] = [:]
    private let popover = NSPopover()
    private let groupPopover = NSPopover()
    private var currentGroup: UUID?
    private let preferences = HubPreferences()
    private var hub: UtilityHub?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        let exportFlag = CommandLine.arguments.contains("--export-live-previews") ? "--export-live-previews" : "--export-previews"
        if let index = CommandLine.arguments.firstIndex(of: exportFlag), CommandLine.arguments.indices.contains(index + 1) {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                do { try await PreviewExporter.export(to: directory, live: exportFlag == "--export-live-previews") }
                catch { fputs("Preview export failed: \(error)\n", stderr) }
                NSApplication.shared.terminate(nil)
            }
            return
        }
        let hub = UtilityHub(preferences: preferences)
        self.hub = hub
        hub.openWindow = { [weak self] tab in self?.showMainWindow(tab: tab) }
        hub.openShelfBar = { [weak self] in
            guard let self, let button = self.moduleItems[.shelf]?.button ?? self.statusItem?.button else { return }
            self.showShelfBar(button, includeTools: self.moduleItems[.shelf] == nil)
        }
        configureMainMenu()
        UNUserNotificationCenter.current().delegate = self

        let item = NSStatusBar.system.statusItem(withLength: 26)
        item.autosaveName = "ThisIsNotFree.Toolbox"
        statusItem = item
        guard let button = item.button else { return }
        button.image = hub.icons.menuImage
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "This Is Not Free · Option-click to reveal menu bar icons"
        button.target = self
        button.action = #selector(togglePopover)

        toolPopover.behavior = .transient
        toolPopover.contentSize = NSSize(width: 420, height: 580)
        popover.behavior = .transient
        groupPopover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 580)
        popover.contentViewController = NSHostingController(rootView: BoxPopoverView(shelf: hub.shelf).environmentObject(hub).environmentObject(preferences))
        hub.shelf.beforeActivation = { [weak self] in self?.shelfBar.close(); self?.popover.performClose(nil); self?.groupPopover.performClose(nil); self?.toolPopover.performClose(nil) }
        preferences.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItems() }
        }.store(in: &subscriptions)
        hub.system.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItems() }
        }.store(in: &subscriptions)
        hub.groups.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItems() }
        }.store(in: &subscriptions)
        hub.icons.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateBranding() }
        }.store(in: &subscriptions)
        updateBranding()
        updateStatusItems()
        DispatchQueue.main.async { [weak self] in self?.showMainWindow() }
    }

    private func updateBranding() {
        guard let hub else { return }
        if appliedAppIcon !== hub.icons.appImage {
            NSApp.applicationIconImage = hub.icons.appImage
            appliedAppIcon = hub.icons.appImage
        }
        statusItem?.button?.image = hub.icons.menuImage
        statusItem?.button?.contentTintColor = preferences.coloredIcon && hub.icons.menuImage.isTemplate ? preferences.accent.nsColor : nil
    }

    private func updateStatusItems() {
        guard let hub else { return }
        if !preferences.enabled(.shelf) { shelfBar.close() }
        statusItem?.button?.contentTintColor = preferences.coloredIcon && hub.icons.menuImage.isTemplate ? preferences.accent.nsColor : nil
        let configured = preferences.menuBarReady
        statusItem?.isVisible = preferences.showsBox
        let desired = Set(preferences.menuBarModules)
        for module in Set(moduleItems.keys).subtracting(desired) {
            if let item = moduleItems.removeValue(forKey: module) { NSStatusBar.system.removeStatusItem(item) }
        }
        for module in desired {
            if moduleItems[module] == nil { hub.shelf.setCollapsed(false) }
            let item = moduleItems[module] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            moduleItems[module] = item
            item.autosaveName = "ThisIsNotFree.Tool.\(module.rawValue)"
            item.button?.image = NSImage(systemSymbolName: module.symbol, accessibilityDescription: module.title)
            item.button?.image?.isTemplate = true
            item.button?.contentTintColor = preferences.coloredIcon ? preferences.accent.nsColor : nil
            item.button?.toolTip = module.title
            item.button?.identifier = NSUserInterfaceItemIdentifier(module.rawValue)
            item.button?.target = self
            item.button?.action = #selector(toggleTool(_:))
        }
        if let currentTool, !desired.contains(currentTool) { toolPopover.performClose(nil) }
        if statusItem?.isVisible == false { popover.performClose(nil) }
        let enabled = configured && preferences.enabled(.system) && preferences.placement(.system) == .individual
        updateMetric(&cpuItem, enabled: enabled && preferences.showCPU, name: "CPU", value: hub.system.cpu)
        updateMetric(&gpuItem, enabled: enabled && preferences.showGPU, name: "GPU", value: hub.system.gpu)
        let groups = preferences.showsCustomGroups ? hub.groups.groups.filter(\.showInMenuBar) : []
        let active = Set(groups.map(\.id))
        for id in Set(groupItems.keys).subtracting(active) {
            if let item = groupItems.removeValue(forKey: id) { NSStatusBar.system.removeStatusItem(item) }
        }
        for group in groups {
            if groupItems[group.id] == nil { hub.shelf.setCollapsed(false) }
            let item = groupItems[group.id] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "ThisIsNotFree.Group.\(group.id)"
            groupItems[group.id] = item
            let image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: group.name)
            image?.isTemplate = true
            item.button?.image = image
            item.button?.toolTip = group.name
            item.button?.identifier = NSUserInterfaceItemIdentifier(group.id.uuidString)
            item.button?.contentTintColor = preferences.coloredIcon ? preferences.accent.nsColor : nil
            item.button?.target = self
            item.button?.action = #selector(toggleGroup(_:))
        }
        if configured && preferences.layout != .window && preferences.enabled(.shelf) { hub.shelf.restoreOrganizerPreference() }
    }

    private func updateMetric(_ item: inout NSStatusItem?, enabled: Bool, name: String, value: Double?) {
        if enabled {
            if item == nil {
                hub?.shelf.setCollapsed(false)
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item?.autosaveName = "ThisIsNotFree.\(name)"
                item?.button?.target = self
                item?.button?.action = #selector(openDashboard)
                item?.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            }
            item?.button?.title = "\(name) \(value.map { String(Int(($0 * 100).rounded())) + "%" } ?? "—")"
        } else if let existing = item { NSStatusBar.system.removeStatusItem(existing); item = nil }
    }

    @objc private func openDashboard() { showMainWindow(tab: "system") }

    @objc private func toggleGroup(_ sender: NSStatusBarButton) {
        shelfBar.close()
        guard let hub, let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        if groupPopover.isShown && currentGroup == id { groupPopover.performClose(nil); return }
        popover.performClose(nil)
        toolPopover.performClose(nil)
        groupPopover.performClose(nil)
        currentGroup = id
        groupPopover.contentViewController = NSHostingController(rootView:
            GroupPanelView(groups: hub.groups, system: hub.system, awake: hub.awake, displays: hub.displays,
                           wifi: hub.wifi, shelf: hub.shelf, groupID: id, edit: { [weak self] in
                self?.groupPopover.performClose(nil); self?.showMainWindow(tab: "shelf")
            }).environmentObject(hub).environmentObject(preferences))
        groupPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    private func showMainWindow(tab: String? = nil) {
        shelfBar.close()
        guard let hub else { return }
        if let tab { hub.tab = tab }
        popover.performClose(nil); groupPopover.performClose(nil); toolPopover.performClose(nil)
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "This Is Not Free"
            window.contentMinSize = NSSize(width: 980, height: 680)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ThisIsNotFree.Workspace.Catalog")
            window.contentViewController = NSHostingController(rootView: WorkspaceView().environmentObject(hub).environmentObject(preferences))
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 1000)
            window.setContentSize(NSSize(width: min(1280, visible.width - 80), height: min(820, visible.height - 80)))
            if !window.setFrameUsingName("ThisIsNotFree.Workspace.Catalog") { window.center() }
            mainWindow = window
        }
        mainWindow?.deminiaturize(nil)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func openWorkspace() { showMainWindow() }
    @objc private func openLayout() { showMainWindow(tab: "layout") }
    @objc private func openSettings() { showMainWindow(tab: "settings") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMainWindow(); return true }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "Open Toolbox", action: #selector(openWorkspace), keyEquivalent: "")
        item.target = self
        return menu
    }
    private func configureMainMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        let root = menu.addItem(withTitle: "This Is Not Free", action: nil, keyEquivalent: "")
        root.submenu = appMenu
        func add(_ title: String, _ action: Selector, _ key: String) {
            let item = appMenu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
        }
        add("Open Toolbox", #selector(openWorkspace), "1")
        add("Tools & Layout…", #selector(openLayout), "l")
        add("Settings…", #selector(openSettings), ",")
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: "Hide This Is Not Free", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"); hide.target = NSApp
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Quit This Is Not Free", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); quit.target = NSApp
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        let windows = NSMenu(title: "Window")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windows
        NSApp.mainMenu = menu; NSApp.windowsMenu = windows
    }
    @objc private func toggleTool(_ sender: NSStatusBarButton) {
        guard hub != nil, let raw = sender.identifier?.rawValue, let module = UtilityModule(rawValue: raw) else { return }
        if module == .shelf { showShelfBar(sender, includeTools: false); return }
        showTool(module, at: sender)
    }
    private func showTool(_ module: UtilityModule, at sender: NSStatusBarButton) {
        guard let hub else { return }
        shelfBar.close()
        if toolPopover.isShown && currentTool == module { toolPopover.performClose(nil); return }
        popover.performClose(nil); groupPopover.performClose(nil); toolPopover.performClose(nil)
        currentTool = module
        toolPopover.contentViewController = NSHostingController(rootView: ToolPopoverView(module: module).environmentObject(hub).environmentObject(preferences))
        toolPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    func applicationWillTerminate(_ notification: Notification) { shelfBar.close(); hub?.shutdown() }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true { hub?.shelf.setCollapsed(false); return }
        if shelfBar.isShown { shelfBar.close(); return }
        if popover.isShown {
            popover.performClose(nil)
        } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        if preferences.enabled(.shelf) && preferences.externalInBox { showShelfBar(button, includeTools: true); return }
        groupPopover.performClose(nil)
        toolPopover.performClose(nil)
        hub?.mixer?.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    private func showShelfBar(_ button: NSStatusBarButton, includeTools: Bool) {
        guard let hub else { return }
        if shelfBar.isShown { shelfBar.close(); return }
        popover.performClose(nil); groupPopover.performClose(nil); toolPopover.performClose(nil)
        shelfBar.show(button: button, hub: hub, preferences: preferences, includeTools: includeTools) { [weak self, weak button] module in
            guard let button else { return }
            self?.showTool(module, at: button)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                             withCompletionHandler completionHandler: @escaping () -> Void) {
        let tab = response.notification.request.identifier == "storage-space" ? "storage" : "settings"
        Task { @MainActor [weak self] in self?.showMainWindow(tab: tab) }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                             withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct MixerView: View {
    @EnvironmentObject private var mixer: MixerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Audio Mixer").font(.headline)
                Spacer()
                Button { mixer.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh audio sources")
            }
            .padding(.horizontal, 18)
            .padding(.top, 17)
            .padding(.bottom, 5)

            Divider()

            Text("Output Devices")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            if mixer.outputDevices.isEmpty {
                Text("No output devices found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(mixer.outputDevices) { device in OutputVolumeRow(device: device) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 190)
            }

            Divider()

            Text("Applications")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            if mixer.apps.isEmpty {
                ContentUnavailableView("No apps playing audio", systemImage: "speaker.slash",
                                       description: Text("Play audio to see an app here."))
                    .frame(height: 110)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(mixer.apps) { app in AppVolumeRow(app: app) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 210)
            }

            if let message = mixer.errorMessage {
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Button { mixer.dismissError() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
                .padding(12)
            }

            Divider()
            HStack(spacing: 10) {
                Button(mixer.requestingPermission ? "Requesting Access…" : "Request Audio Access") {
                    mixer.requestPermission()
                }
                .disabled(mixer.requestingPermission)
                Button("Open Privacy Settings") { mixer.openPermissionSettings() }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            HStack {
                Text("Allow this app in Screen & System Audio Recording.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
    }
}

struct OutputVolumeRow: View {
    @EnvironmentObject private var mixer: MixerModel
    let device: OutputDevice

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: device.isDefault ? "speaker.wave.2.fill" : "hifispeaker.fill")
                .font(.title3)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(device.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text("\(Int((mixer.outputVolume(for: device) * 100).rounded()))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(device.supportsHardwareVolume ?
                     (device.isDefault ? "Default · Device volume" : "Device volume") :
                     (device.isDefault ? "Default · Software · active apps" : "Software · active apps"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(get: { mixer.outputVolume(for: device) },
                                      set: { mixer.setOutputVolume($0, for: device) }), in: 0...1)
                    .accessibilityLabel("\(device.name) output volume")
            }
        }
        .padding(.vertical, 5)
    }
}

private struct AppVolumeRow: View {
    @EnvironmentObject private var mixer: MixerModel
    let app: AudioApp

    var body: some View {
        HStack(spacing: 11) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 30, height: 30)
            } else {
                Image(systemName: "app.fill").font(.title2).frame(width: 30, height: 30)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(app.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text("\(Int((mixer.volume(for: app) * 100).rounded()))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { mixer.volume(for: app) },
                                      set: { mixer.setVolume($0, for: app) }), in: 0...1)
                    .accessibilityLabel("\(app.name) volume")
                HStack(spacing: 4) {
                    Text("Output:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("Output device", selection: Binding(get: { mixer.outputSelection(for: app) },
                                                              set: { mixer.setOutputDevice($0, for: app) })) {
                        Text("Original Output").tag("")
                        let selected = mixer.outputSelection(for: app)
                        if !selected.isEmpty && !mixer.outputDevices.contains(where: { $0.uid == selected }) {
                            Text("Unavailable · Original Output").tag(selected)
                        }
                        ForEach(mixer.outputDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("\(app.name) output device")
                }
            }
            Button {
                mixer.setVolume(mixer.volume(for: app) == 0 ? 1 : 0, for: app)
            } label: {
                Image(systemName: mixer.volume(for: app) == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 23)
            }
            .buttonStyle(.borderless)
            .help("Mute \(app.name)")
        }
        .padding(.vertical, 5)
    }
}
