import AppKit
import Combine
import SwiftUI
import ServiceManagement

@MainActor
final class UtilityHub: ObservableObject {
    let preferences: HubPreferences
    let system = SystemMonitor()
    let awake = AwakeController()
    let displays = DisplayController()
    let shelf = MenuShelf()
    let updates = UpdateChecker()
    let menuBarTint = MenuBarTintController()
    let groups = ToolGroups()
    let wifi = WiFiController()
    @Published private(set) var mixer: MixerModel?
    @Published var tab = "home"
    @Published var loginError: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var subscription: AnyCancellable?
    private var groupSubscription: AnyCancellable?
    private let preview: Bool

    init(preferences: HubPreferences, preview: Bool = false) {
        self.preferences = preferences
        self.preview = preview
        subscription = preferences.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.configure() }
        }
        groupSubscription = groups.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.configure() }
        }
        configure()
    }
    func configure() {
        guard !preview else { return }
        guard preferences.setupComplete else { shutdown(); return }
        if preferences.enabled(.audio) { if mixer == nil { mixer = MixerModel() } } else { mixer = nil }
        let groupedSystem = preferences.enabled(.shelf) && groups.groups.contains { $0.showInMenuBar && $0.members.contains(where: { ["system:battery", "tool:system"].contains($0) }) }
        if preferences.enabled(.system) || groupedSystem { system.start() } else { system.stop() }
        wifi.refresh()
        if !preferences.enabled(.awake) { awake.stop() }
        if !preferences.enabled(.displays) { displays.restoreAll() }
        if !preferences.enabled(.shelf) { shelf.restore() }
        if preferences.enabled(.updates) { updates.start() } else { updates.stop() }
        menuBarTint.configure(enabled: preferences.menuBarTint, color: preferences.accent.nsColor, strength: preferences.tintStrength)
        if tab == "audio" && !preferences.enabled(.audio) || tab == "shelf" && !preferences.enabled(.shelf) { tab = "home" }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        Task {
            do {
                if enabled { try SMAppService.mainApp.register() } else { try await SMAppService.mainApp.unregister() }
                launchAtLogin = SMAppService.mainApp.status == .enabled
                loginError = launchAtLogin == enabled ? nil : "Approve this app in System Settings → Login Items."
            } catch { loginError = "Login item could not be changed. Install the app in Applications and try again." }
        }
    }
    func shutdown() {
        awake.stop(); displays.restoreAll(); shelf.shutdown(); system.stop(); updates.stop(); menuBarTint.stop(); mixer = nil
    }
}

struct HubView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "shippingbox.fill").foregroundStyle(preferences.accent.color).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This Is Not Free").font(.headline)
                    Text("Your Mac, your toolbox. Actually free.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if preferences.setupComplete {
                    Button { hub.tab = "settings" } label: { Image(systemName: "gearshape") }.buttonStyle(.borderless)
                }
            }.padding(16)
            Divider()
            if !preferences.setupComplete {
                SetupView(groups: hub.groups)
            } else {
                Picker("Toolbox", selection: $hub.tab) {
                    Text("Home").tag("home")
                    if preferences.enabled(.audio) { Text("Audio").tag("audio") }
                    if preferences.enabled(.shelf) { Text("Shelf").tag("shelf") }
                    Text("Settings").tag("settings")
                }.pickerStyle(.segmented).labelsHidden().padding(12)
                switch hub.tab {
                case "audio":
                    if let mixer = hub.mixer { MixerView().environmentObject(mixer) }
                case "shelf": ShelfView(shelf: hub.shelf, groups: hub.groups)
                case "settings": HubSettingsView(updates: hub.updates)
                default: DashboardView(system: hub.system, awake: hub.awake, displays: hub.displays, updates: hub.updates)
                }
                Spacer(minLength: 0)
                Divider()
                HStack {
                    Text("v\(hub.updates.currentVersion)").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless)
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .frame(width: 420, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(preferences.accent.color)
        .preferredColorScheme(preferences.appearance == "dark" ? .dark : preferences.appearance == "light" ? .light : nil)
    }
}

private struct SetupView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    @ObservedObject var groups: ToolGroups
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Build your toolbox").font(.title2.bold())
            Text("Choose what belongs in your menu bar. You can change this anytime in Settings.")
                .font(.subheadline).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(UtilityModule.allCases) { module in ModuleToggle(module: module) }
                    Divider()
                    Toggle("CPU percentage in the menu bar", isOn: $preferences.showCPU)
                    Toggle("GPU percentage in the menu bar", isOn: $preferences.showGPU)
                    if let group = groups.groups.first {
                        Toggle("One Essentials icon for Wi-Fi, battery, audio, and awake", isOn: Binding(get: { groups.groups.first?.showInMenuBar ?? false }, set: { value in groups.update(group.id) { $0.showInMenuBar = value } }))
                    }
                }
            }
            Button("Start using This Is Not Free") { preferences.setupComplete = true }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            Text("Permissions are requested only for the tools you enable.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(20)
    }
}

private struct ModuleToggle: View {
    @EnvironmentObject var preferences: HubPreferences
    let module: UtilityModule
    var body: some View {
        Toggle(isOn: Binding(get: { preferences.enabled(module) }, set: { preferences.set(module, enabled: $0) })) {
            HStack(spacing: 10) {
                Image(systemName: module.symbol).frame(width: 24).foregroundStyle(preferences.accent.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(module.title).font(.subheadline.weight(.medium))
                    Text(module.detail).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(.switch).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    @ObservedObject var system: SystemMonitor
    @ObservedObject var awake: AwakeController
    @ObservedObject var displays: DisplayController
    @ObservedObject var updates: UpdateChecker
    @State private var minutes = 30
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if updates.release != nil && preferences.enabled(.updates) {
                    Button { updates.openRelease() } label: {
                        Label(updates.message, systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.borderedProminent)
                }
                if preferences.enabled(.system) {
                    Text("System Monitor").font(.headline)
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                        MetricCard(title: "CPU", value: percent(system.cpu), fraction: system.cpu)
                        MetricCard(title: "GPU", value: percent(system.gpu), fraction: system.gpu)
                        MetricCard(title: "Memory", value: ByteCountFormatter.string(fromByteCount: Int64(system.memoryUsed), countStyle: .memory), fraction: Double(system.memoryUsed) / Double(system.memoryTotal))
                        MetricCard(title: "Disk", value: percent(system.diskUsed), fraction: system.diskUsed)
                    }
                    Text(system.gpuName + (system.gpu == nil ? " · Usage counter unavailable" : ""))
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Label("↓ \(rate(system.download))", systemImage: "network")
                        Spacer()
                        Text("↑ \(rate(system.upload))")
                    }.font(.caption.monospacedDigit())
                    if let battery = system.battery {
                        HStack { Label("Battery", systemImage: "battery.100percent"); Spacer(); Text(percent(battery)) }.font(.caption)
                    }
                }
                if preferences.enabled(.awake) {
                    Divider()
                    HStack { Label("Keep Awake", systemImage: "bolt.shield.fill").font(.headline); Spacer(); Text(awake.active ? "On" : "Off").foregroundStyle(awake.active ? .green : .secondary) }
                    HStack {
                        Picker("Duration", selection: $minutes) {
                            Text("15 min").tag(15); Text("30 min").tag(30); Text("1 hour").tag(60); Text("2 hours").tag(120); Text("Until stopped").tag(0)
                        }.labelsHidden()
                        Button(awake.active ? "Stop" : "Keep Awake") { awake.active ? awake.stop() : awake.start(minutes: minutes) }.buttonStyle(.borderedProminent)
                    }
                    if let end = awake.endsAt { HStack { Text("Remaining"); Spacer(); Text(end, style: .timer).monospacedDigit() }.font(.caption) }
                    if let error = awake.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    Text("Prevents idle sleep. Closing the lid or choosing Sleep still works.").font(.caption2).foregroundStyle(.secondary)
                }
                if preferences.enabled(.displays) {
                    Divider()
                    HStack { Label("Display Dimming", systemImage: "sun.max.fill").font(.headline); Spacer(); Button("Restore All") { displays.restoreAll() }.buttonStyle(.borderless) }
                    ForEach(displays.displays) { display in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(display.name); Spacer(); Text(percent(display.brightness)).monospacedDigit() }.font(.caption)
                            Slider(value: Binding(get: { displays.displays.first(where: { $0.id == display.id })?.brightness ?? 1 }, set: { displays.setBrightness($0, display: display) }), in: 0.2...1)
                        }
                    }
                    Text("Software dimming changes the image, not the monitor's hardware backlight. Reset automatically when the app quits.").font(.caption2).foregroundStyle(.secondary)
                }
                if !preferences.enabled(.system) && !preferences.enabled(.awake) && !preferences.enabled(.displays) {
                    ContentUnavailableView("Your toolbox is ready", systemImage: "shippingbox", description: Text("Open a tab or enable more tools in Settings."))
                }
            }.padding(16)
        }
    }
    private func percent(_ value: Double?) -> String { value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    private func rate(_ bytes: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(max(bytes, 0)), countStyle: .decimal) + "/s" }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let fraction: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            ProgressView(value: min(max(fraction ?? 0, 0), 1)).opacity(fraction == nil ? 0.3 : 1)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ShelfView: View {
    @ObservedObject var shelf: MenuShelf
    @ObservedObject var groups: ToolGroups
    @State private var search = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupEditorView(groups: groups, shelf: shelf)
                Divider()
                HStack {
                    Text("Menu Bar Shelf").font(.headline)
                    Spacer()
                    Button { shelf.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(shelf.refreshing)
                }
                if !shelf.accessibilityGranted {
                    Text("Allow Accessibility to discover menu bar items and open their original menus from your shelf.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Enable Accessibility") { shelf.requestAccessibility() }.buttonStyle(.borderedProminent)
                } else {
                    if !shelf.pinnedItems.isEmpty {
                        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 4), spacing: 12) {
                            ForEach(shelf.pinnedItems) { item in
                                Button { shelf.activate(item) } label: {
                                    VStack(spacing: 5) {
                                        if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 30, height: 30) }
                                        else { Image(systemName: "app").font(.title) }
                                        Text(item.title).font(.caption2).lineLimit(2)
                                    }.frame(maxWidth: .infinity, minHeight: 62)
                                }.buttonStyle(.borderless).help(item.appName)
                            }
                        }
                    }
                    TextField("Find a menu bar item", text: $search).textFieldStyle(.roundedBorder)
                    if shelf.refreshing { ProgressView("Reading menu bar items…").font(.caption) }
                    ForEach(shelf.items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.appName.localizedCaseInsensitiveContains(search) }) { item in
                        HStack {
                            if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                            Button { shelf.activate(item) } label: {
                                VStack(alignment: .leading) { Text(item.title).font(.subheadline); Text(item.appName).font(.caption2).foregroundStyle(.secondary) }
                            }.buttonStyle(.borderless)
                            Spacer()
                            Button { shelf.togglePin(item) } label: { Image(systemName: shelf.pinned.contains(item.id) ? "pin.fill" : "pin") }.buttonStyle(.borderless).help("Pin to shelf")
                        }
                    }
                    Text("Shelf tiles use app icons. Clicking one reveals the menu bar and presses the original item.").font(.caption2).foregroundStyle(.secondary)
                    if shelf.pinned.count > shelf.pinnedItems.count {
                        Button("Remove Unavailable Pins") { shelf.removeUnavailablePins() }.font(.caption)
                    }
                }
                if let message = shelf.message { Text(message).font(.caption).foregroundStyle(.orange) }
                Divider()
                Toggle("Enable a collapsible menu bar section", isOn: Binding(get: { shelf.organizerEnabled }, set: { shelf.enableOrganizer($0) }))
                    .disabled(!shelf.supportsCollapse)
                if shelf.supportsCollapse {
                    Text("Hold ⌘ and drag icons to the left of the │ divider. Collapse hides that section; Reveal brings it back.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(shelf.collapsed ? "Reveal Icons" : "Collapse Icons") { shelf.setCollapsed(!shelf.collapsed) }.disabled(!shelf.organizerEnabled)
                        Button("Restore Menu Bar") { shelf.restore() }
                    }
                } else {
                    Text("Section collapsing is unavailable on macOS 27 and later. Shelf shortcuts still work with Accessibility.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16)
        }.onAppear { shelf.refresh() }
    }
}

private struct GroupEditorView: View {
    @ObservedObject var groups: ToolGroups
    @ObservedObject var shelf: MenuShelf
    @State private var editing: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Menu Bar Groups").font(.headline); Spacer(); Button("New Group") { editing = groups.add() } }
            Text("Mix built-in tools and other apps under one menu bar icon.").font(.caption).foregroundStyle(.secondary)
            ForEach(groups.groups) { group in
                HStack {
                    Image(systemName: group.symbol)
                    Text(group.name.isEmpty ? "Untitled Group" : group.name)
                    Spacer()
                    Toggle("Show", isOn: Binding(get: { group.showInMenuBar }, set: { value in groups.update(group.id) { $0.showInMenuBar = value } })).labelsHidden().toggleStyle(.switch)
                    Button(editing == group.id ? "Done" : "Edit") { editing = editing == group.id ? nil : group.id }
                }
                if editing == group.id {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Group name", text: Binding(get: { group.name }, set: { value in groups.update(group.id) { $0.name = String(value.prefix(40)) } })).textFieldStyle(.roundedBorder)
                        Picker("Icon", selection: Binding(get: { group.symbol }, set: { value in groups.update(group.id) { $0.symbol = value } })) {
                            ForEach(ToolGroup.symbols, id: \.self) { Image(systemName: $0).tag($0) }
                        }
                        if !group.members.isEmpty { Text("Popup order").font(.caption.weight(.semibold)) }
                        ForEach(group.members, id: \.self) { member in
                            HStack {
                                Text(memberName(member)).font(.caption).lineLimit(1)
                                Spacer()
                                Button { groups.moveMember(member, group: group.id, offset: -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless)
                                Button { groups.moveMember(member, group: group.id, offset: 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.borderless)
                            }
                        }
                        Divider()
                        ForEach(ToolGroup.builtIns, id: \.id) { member in memberRow(member.id, name: member.name, group: group) }
                        if !shelf.items.isEmpty { Text("Other menu bar items").font(.caption.weight(.semibold)) }
                        ForEach(shelf.items) { item in memberRow("external:" + item.id, name: item.title + " · " + item.appName, group: group) }
                        Button("Delete Group", role: .destructive) { groups.remove(group.id); editing = nil }
                    }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text("Original system and third-party icons remain owned by macOS and their apps. Use the collapsible section below or macOS Menu Bar settings to hide those originals.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func memberRow(_ id: String, name: String, group: ToolGroup) -> some View {
        Toggle(name, isOn: Binding(get: { group.members.contains(id) }, set: { _ in groups.toggleMember(id, group: group.id) })).font(.caption)
    }
    private func memberName(_ member: String) -> String {
        if let builtIn = ToolGroup.builtIns.first(where: { $0.id == member }) { return builtIn.name }
        return shelf.items.first(where: { "external:" + $0.id == member })?.title ?? "Unavailable menu item"
    }
}

struct GroupPanelView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    @ObservedObject var groups: ToolGroups
    @ObservedObject var system: SystemMonitor
    @ObservedObject var awake: AwakeController
    @ObservedObject var displays: DisplayController
    @ObservedObject var wifi: WiFiController
    @ObservedObject var shelf: MenuShelf
    let groupID: UUID
    let edit: () -> Void
    var body: some View {
        let group = groups.groups.first(where: { $0.id == groupID })
        VStack(spacing: 0) {
            HStack { Label(group?.name ?? "Group", systemImage: group?.symbol ?? "square.grid.2x2").font(.headline); Spacer(); Button("Edit", action: edit).buttonStyle(.borderless) }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if group?.members.isEmpty != false { Text("Add tools and menu bar items using Edit.").foregroundStyle(.secondary) }
                    ForEach(group?.members ?? [], id: \.self) { member in
                        groupMember(member)
                        Divider()
                    }
                }.padding(16)
            }
        }.frame(width: 360, height: 500).tint(preferences.accent.color)
            .preferredColorScheme(preferences.appearance == "dark" ? .dark : preferences.appearance == "light" ? .light : nil)
            .onAppear { wifi.refresh(); shelf.refresh() }
    }
    @ViewBuilder private func groupMember(_ member: String) -> some View {
        switch member {
        case "system:wifi":
            HStack {
                Label("Wi-Fi", systemImage: "wifi")
                Spacer()
                Button(wifi.powered.map { $0 ? "Turn Off" : "Turn On" } ?? "Unavailable") { wifi.toggle() }.disabled(wifi.busy || wifi.powered == nil)
            }
            if let error = wifi.error { Text(error).font(.caption).foregroundStyle(.orange) }
        case "system:battery":
            HStack { Label("Battery", systemImage: "battery.100percent"); Spacer(); Text(system.battery.map { "\(Int(($0 * 100).rounded()))%" } ?? "No battery") }
        case "tool:system":
            HStack {
                MetricCard(title: "CPU", value: system.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", fraction: system.cpu)
                MetricCard(title: "Memory", value: ByteCountFormatter.string(fromByteCount: Int64(system.memoryUsed), countStyle: .memory), fraction: Double(system.memoryUsed) / Double(system.memoryTotal))
            }
        case "tool:awake":
            if preferences.enabled(.awake) {
                HStack { Label("Keep Awake", systemImage: "bolt.shield.fill"); Spacer(); Button(awake.active ? "Stop" : "Start 1 Hour") { awake.active ? awake.stop() : awake.start(minutes: 60) } }
                if let end = awake.endsAt { Text(end, style: .timer).font(.caption.monospacedDigit()) }
            } else { disabledTool("Keep Awake") }
        case "tool:audio":
            if let mixer = hub.mixer { GroupAudioView(mixer: mixer) } else { disabledTool("Audio Mixer") }
        case "tool:displays":
            if preferences.enabled(.displays) {
                ForEach(displays.displays) { display in
                    VStack(alignment: .leading) {
                        Label(display.name, systemImage: "sun.max").font(.caption)
                        Slider(value: Binding(get: { displays.displays.first(where: { $0.id == display.id })?.brightness ?? 1 }, set: { displays.setBrightness($0, display: display) }), in: 0.2...1)
                    }
                }
                Button("Restore Displays") { displays.restoreAll() }
            } else { disabledTool("Display Dimming") }
        default:
            if member.hasPrefix("external:"), let item = shelf.items.first(where: { $0.id == String(member.dropFirst(9)) }) {
                Button { shelf.activate(item) } label: {
                    HStack { if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }; Text(item.title); Spacer(); Image(systemName: "arrow.up.right") }
                }.buttonStyle(.borderless)
            } else { Text("Menu item unavailable · Refresh in Shelf").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func disabledTool(_ name: String) -> some View { Text("Enable \(name) in Toolbox Settings to use it here.").font(.caption).foregroundStyle(.secondary) }
}

private struct GroupAudioView: View {
    @ObservedObject var mixer: MixerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Audio Outputs", systemImage: "speaker.wave.2").font(.subheadline.weight(.semibold))
            if mixer.outputDevices.isEmpty { Text("No output devices found").font(.caption).foregroundStyle(.secondary) }
            ForEach(mixer.outputDevices) { device in OutputVolumeRow(device: device).environmentObject(mixer) }
        }
    }
}

private struct HubSettingsView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    @ObservedObject var updates: UpdateChecker
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Toolbox").font(.headline)
                ForEach(UtilityModule.allCases) { ModuleToggle(module: $0) }
                Divider()
                Text("Appearance").font(.headline)
                Picker("Style", selection: $preferences.appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                Picker("Accent", selection: $preferences.accent) { ForEach(HubAccent.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Toggle("Color the toolbox menu bar icon", isOn: $preferences.coloredIcon)
                Toggle("Tint the macOS menu bar", isOn: $preferences.menuBarTint)
                if preferences.menuBarTint {
                    Slider(value: $preferences.tintStrength, in: 0.03...0.22) { Text("Tint strength") }
                    Text("A click-through tint covers the bar and its icons. It follows the accent color and is removed when you quit.").font(.caption2).foregroundStyle(.secondary)
                }
                Toggle("Show CPU in menu bar", isOn: $preferences.showCPU).disabled(!preferences.enabled(.system))
                Toggle("Show GPU in menu bar", isOn: $preferences.showGPU).disabled(!preferences.enabled(.system))
                Text("Accent and style also customize this toolbox's popup.").font(.caption2).foregroundStyle(.secondary)
                Divider()
                Toggle("Launch at login", isOn: Binding(get: { hub.launchAtLogin }, set: { hub.setLaunchAtLogin($0) }))
                if let error = hub.loginError { Text(error).font(.caption).foregroundStyle(.orange) }
                if preferences.enabled(.updates) {
                    Divider()
                    Text("Updates").font(.headline)
                    Text(updates.message).font(.subheadline)
                    if let date = updates.checkedAt { Text("Checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
                    HStack {
                        Button(updates.checking ? "Checking…" : "Check Now") { updates.check() }.disabled(updates.checking)
                        Button("View Releases") { updates.openRelease() }
                    }
                    Button(updates.notificationsEnabled ? "Notifications Enabled" : "Enable Update Notifications") { updates.enableNotifications() }.disabled(updates.notificationsEnabled)
                    Text("Checks every six hours while running. Updates open on GitHub for you to download.").font(.caption2).foregroundStyle(.secondary)
                }
                Divider()
                Link("Source · JoonNeuro/ThisIsNotFree", destination: URL(string: "https://github.com/JoonNeuro/ThisIsNotFree")!)
                Button("Customize from the beginning") { hub.tab = "home"; preferences.setupComplete = false }
            }.padding(16)
        }
    }
}
