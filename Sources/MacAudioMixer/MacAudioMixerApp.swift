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
        NSApplication.shared.setActivationPolicy(.accessory)
        if let index = CommandLine.arguments.firstIndex(of: "--export-previews"), CommandLine.arguments.indices.contains(index + 1) {
            do { try PreviewExporter.export(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("Preview export failed: \(error)\n", stderr) }
            NSApplication.shared.terminate(nil)
            return
        }
        let hub = UtilityHub(preferences: preferences)
        self.hub = hub
        UNUserNotificationCenter.current().delegate = self

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "ThisIsNotFree.Toolbox"
        statusItem = item
        guard let button = item.button else { return }
        if let image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "This Is Not Free") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "♫"
        }
        button.toolTip = "This Is Not Free · Option-click to reveal menu bar icons"
        button.target = self
        button.action = #selector(togglePopover)

        popover.behavior = .transient
        groupPopover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 640)
        popover.contentViewController = NSHostingController(rootView: HubView().environmentObject(hub).environmentObject(preferences))
        hub.shelf.beforeActivation = { [weak self] in self?.popover.performClose(nil); self?.groupPopover.performClose(nil) }
        preferences.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItems() }
        }.store(in: &subscriptions)
        hub.system.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItems() }
        }.store(in: &subscriptions)
        hub.groups.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItems() }
        }.store(in: &subscriptions)
        updateStatusItems()
        if !preferences.setupComplete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showPopover() }
        }
    }

    private func updateStatusItems() {
        guard let hub else { return }
        statusItem?.button?.contentTintColor = preferences.coloredIcon ? preferences.accent.nsColor : nil
        let enabled = preferences.setupComplete && preferences.enabled(.system)
        updateMetric(&cpuItem, enabled: enabled && preferences.showCPU, name: "CPU", value: hub.system.cpu)
        updateMetric(&gpuItem, enabled: enabled && preferences.showGPU, name: "GPU", value: hub.system.gpu)
        let groups = preferences.setupComplete && preferences.enabled(.shelf) ? hub.groups.groups.filter(\.showInMenuBar) : []
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
        if preferences.setupComplete && preferences.enabled(.shelf) { hub.shelf.restoreOrganizerPreference() }
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

    @objc private func openDashboard() { hub?.tab = "home"; showPopover() }

    @objc private func toggleGroup(_ sender: NSStatusBarButton) {
        guard let hub, let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        if groupPopover.isShown && currentGroup == id { groupPopover.performClose(nil); return }
        popover.performClose(nil)
        groupPopover.performClose(nil)
        currentGroup = id
        groupPopover.contentViewController = NSHostingController(rootView:
            GroupPanelView(groups: hub.groups, system: hub.system, awake: hub.awake, displays: hub.displays,
                           wifi: hub.wifi, shelf: hub.shelf, groupID: id, edit: { [weak self] in
                self?.groupPopover.performClose(nil); self?.hub?.tab = "shelf"; self?.showPopover()
            }).environmentObject(hub).environmentObject(preferences))
        groupPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    func applicationWillTerminate(_ notification: Notification) { hub?.shutdown() }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true { hub?.shelf.setCollapsed(false); return }
        if popover.isShown {
            popover.performClose(nil)
        } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        groupPopover.performClose(nil)
        hub?.mixer?.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                             withCompletionHandler completionHandler: @escaping () -> Void) {
        let tab = response.notification.request.identifier == "storage-space" ? "storage" : "settings"
        Task { @MainActor [weak self] in self?.hub?.tab = tab; self?.showPopover() }
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
