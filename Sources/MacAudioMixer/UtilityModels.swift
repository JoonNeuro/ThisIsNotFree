import AppKit
import Combine
import Metal
import MixerCore
import SwiftUI

enum UtilityModule: String, CaseIterable, Identifiable {
    case system, audio, awake, displays, shelf, notch, storage, updates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System Monitor"
        case .audio: return "Audio Mixer"
        case .awake: return "Keep Awake"
        case .displays: return "Display Dimming"
        case .shelf: return "Menu Bar Shelf"
        case .notch: return "Notch Hub"
        case .storage: return "Storage Tracker"
        case .updates: return "GitHub Updates"
        }
    }
    var symbol: String {
        switch self {
        case .system: return "chart.xyaxis.line"
        case .audio: return "slider.horizontal.3"
        case .awake: return "bolt.shield.fill"
        case .displays: return "sun.max"
        case .shelf: return "archivebox"
        case .notch: return "macbook.gen2"
        case .storage: return "internaldrive"
        case .updates: return "arrow.down.circle"
        }
    }
    var detail: String {
        switch self {
        case .system: return "CPU, GPU, memory, network, disk, and battery."
        case .audio: return "Per-app volume and output device routing."
        case .awake: return "Keep your display awake for a set time."
        case .displays: return "Dim each screen with a click-through shade."
        case .shelf: return "Pin menu items and collapse a menu bar section."
        case .notch: return "Wi-Fi dots and a battery rail beside the camera."
        case .storage: return "Disk space history and watched-folder changes."
        case .updates: return "Check this project's GitHub releases."
        }
    }
}

enum ToolCategory: String, CaseIterable, Identifiable {
    case system, sound, focus, menuBar, app
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "System & Storage"; case .sound: return "Sound & Display"; case .focus: return "Focus & Power"; case .menuBar: return "Menu Bar"; case .app: return "App & Updates" }
    }
    var modules: [UtilityModule] { UtilityModule.allCases.filter { $0.category == self } }
}

extension UtilityModule {
    var category: ToolCategory {
        switch self { case .system, .storage: return .system; case .audio, .displays: return .sound; case .awake: return .focus; case .shelf, .notch: return .menuBar; case .updates: return .app }
    }
    var color: Color {
        switch self { case .system: return .mint; case .storage: return .orange; case .audio: return .purple; case .displays: return .yellow; case .awake: return .cyan; case .shelf: return .pink; case .notch: return .mint; case .updates: return .green }
    }
    var features: [String] {
        switch self {
        case .system: return ["CPU, GPU, and memory at a glance", "Network transfer rates and battery status", "Optional CPU and GPU menu bar indicators"]
        case .storage: return ["Free-space history for your startup disk", "Choose folders and compare file changes", "Alerts when free space suddenly drops"]
        case .audio: return ["Set the volume of each active app", "Send different apps to different speakers", "Adjust hardware or supported software output volume"]
        case .displays: return ["Independent software dimming for each display", "Quickly restore every screen", "Click-through shades removed when the app quits"]
        case .awake: return ["Prevent idle system and display sleep", "Set a timer or keep awake until stopped", "Closing the lid and manual Sleep still work"]
        case .shelf: return ["Collect accessible menu items in one popup", "Mix built-in controls and third-party shortcuts", "Collapse a manually arranged section on supported macOS"]
        case .notch: return ["Three vertical Wi-Fi dots on the left", "A vertical battery rail on the right, with accessory segments", "Open original system menus; optional full-contour layout"]
        case .updates: return ["Check this project's published GitHub releases", "Optional update notifications", "Open verified release pages to download updates"]
        }
    }
}

enum HubAccent: String, CaseIterable, Identifiable {
    case blue, purple, orange, green, pink
    var id: String { rawValue }
    var color: Color {
        switch self { case .blue: return .blue; case .purple: return .purple; case .orange: return .orange; case .green: return .green; case .pink: return .pink }
    }
    var nsColor: NSColor {
        switch self { case .blue: return .systemBlue; case .purple: return .systemPurple; case .orange: return .systemOrange; case .green: return .systemGreen; case .pink: return .systemPink }
    }
}

enum ToolPlacement: String, CaseIterable, Identifiable {
    case box, individual, window
    var id: String { rawValue }
    var title: String {
        switch self { case .box: return "In the Box"; case .individual: return "Own Icon"; case .window: return "App Only" }
    }
}

enum LayoutPreset: String, CaseIterable, Identifiable {
    case box, individual, window, custom
    var id: String { rawValue }
    var title: String {
        switch self { case .box: return "One Box"; case .individual: return "Individual Icons"; case .window: return "App Only"; case .custom: return "Custom Mix" }
    }
    var symbol: String {
        switch self { case .box: return "shippingbox.fill"; case .individual: return "rectangle.split.3x1"; case .window: return "macwindow"; case .custom: return "slider.horizontal.3" }
    }
    var detail: String {
        switch self {
        case .box: return "One menu bar icon opens your selected tools and connected menu items."
        case .individual: return "Give each selected tool its own menu bar icon. Existing icons stay in place."
        case .window: return "Use tools in the app window, with no toolbox menu bar icons."
        case .custom: return "Choose a separate icon, the shared box, or app-only access for each tool."
        }
    }
}

@MainActor
final class HubPreferences: ObservableObject {
    @Published var workspaceConfigured: Bool { didSet { defaults.set(workspaceConfigured, forKey: "hub.workspaceConfigured") } }
    @Published var layout: LayoutPreset { didSet { defaults.set(layout.rawValue, forKey: "hub.layout") } }
    @Published private(set) var placements: [String: String] { didSet { defaults.set(placements, forKey: "hub.placements") } }
    @Published var externalInBox: Bool { didSet { defaults.set(externalInBox, forKey: "hub.externalInBox") } }
    @Published var includeAllExternal: Bool { didSet { defaults.set(includeAllExternal, forKey: "hub.includeAllExternal") } }
    @Published var modules: Set<String> { didSet { defaults.set(Array(modules), forKey: "hub.modules") } }
    @Published var setupComplete: Bool { didSet { defaults.set(setupComplete, forKey: "hub.setupComplete") } }
    @Published var accent: HubAccent { didSet { defaults.set(accent.rawValue, forKey: "hub.accent") } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "hub.appearance") } }
    @Published var showCPU: Bool { didSet { defaults.set(showCPU, forKey: "hub.showCPU") } }
    @Published var showGPU: Bool { didSet { defaults.set(showGPU, forKey: "hub.showGPU") } }
    @Published var coloredIcon: Bool { didSet { defaults.set(coloredIcon, forKey: "hub.coloredIcon") } }
    @Published var menuBarTint: Bool { didSet { defaults.set(menuBarTint, forKey: "hub.menuBarTint") } }
    @Published var tintStrength: Double { didSet { defaults.set(tintStrength, forKey: "hub.tintStrength") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let legacy = defaults.persistentDomain(forName: "com.example.MacAudioMixer") {
            for key in ["appVolumes", "softwareDeviceVolumes", "appOutputDevices"] where defaults.object(forKey: key) == nil {
                if let value = legacy[key] { defaults.set(value, forKey: key) }
            }
        }
        workspaceConfigured = defaults.bool(forKey: "hub.workspaceConfigured")
        layout = LayoutPreset(rawValue: defaults.string(forKey: "hub.layout") ?? "box") ?? .box
        placements = defaults.dictionary(forKey: "hub.placements") as? [String: String] ?? [:]
        externalInBox = defaults.object(forKey: "hub.externalInBox") as? Bool ?? true
        includeAllExternal = defaults.object(forKey: "hub.includeAllExternal") as? Bool ?? true
        modules = Set(defaults.stringArray(forKey: "hub.modules") ?? [])
        setupComplete = defaults.bool(forKey: "hub.setupComplete")
        accent = HubAccent(rawValue: defaults.string(forKey: "hub.accent") ?? "blue") ?? .blue
        appearance = defaults.string(forKey: "hub.appearance") ?? "system"
        showCPU = defaults.bool(forKey: "hub.showCPU")
        showGPU = defaults.bool(forKey: "hub.showGPU")
        coloredIcon = defaults.bool(forKey: "hub.coloredIcon")
        menuBarTint = defaults.bool(forKey: "hub.menuBarTint")
        tintStrength = defaults.object(forKey: "hub.tintStrength") as? Double ?? 0.12
    }
    func placement(_ module: UtilityModule) -> ToolPlacement {
        if let raw = placements[module.rawValue], let value = ToolPlacement(rawValue: raw) { return value }
        return layout == .individual ? .individual : layout == .window ? .window : .box
    }
    var menuBarReady: Bool { setupComplete && workspaceConfigured }
    var showsBox: Bool { !menuBarReady || !boxModules.isEmpty || (enabled(.shelf) && externalInBox) }
    var menuBarModules: [UtilityModule] { menuBarReady ? individualModules : [] }
    var showsCustomGroups: Bool { menuBarReady && layout == .custom && enabled(.shelf) }
    var boxModules: [UtilityModule] { UtilityModule.allCases.filter { enabled($0) && placement($0) == .box } }
    var individualModules: [UtilityModule] { UtilityModule.allCases.filter { enabled($0) && placement($0) == .individual } }
    func setPlacement(_ module: UtilityModule, _ placement: ToolPlacement) {
        placements[module.rawValue] = placement.rawValue
        layout = .custom
    }
    func applyLayout(_ preset: LayoutPreset) {
        if preset != .custom {
            let placement: ToolPlacement = preset == .box ? .box : preset == .individual ? .individual : .window
            placements = Dictionary(uniqueKeysWithValues: UtilityModule.allCases.map { ($0.rawValue, placement.rawValue) })
            externalInBox = preset == .box
            if preset == .box { includeAllExternal = true }
        }
        layout = preset
    }
    func activate(_ module: UtilityModule) {
        set(module, enabled: true)
        workspaceConfigured = true
        setupComplete = true
    }
    func enabled(_ module: UtilityModule) -> Bool { modules.contains(module.rawValue) }
    func set(_ module: UtilityModule, enabled: Bool) {
        if enabled { modules.insert(module.rawValue) } else { modules.remove(module.rawValue) }
    }
}

struct CPUSample {
    let busy: UInt64
    let idle: UInt64
    func usage(since previous: CPUSample) -> Double? {
        guard busy >= previous.busy, idle >= previous.idle else { return nil }
        let active = Double(busy - previous.busy)
        let total = active + Double(idle - previous.idle)
        return total > 0 ? active / total : nil
    }
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var hasSample = false
    @Published private(set) var hasNetworkInterval = false
    @Published private(set) var cpu: Double?
    @Published private(set) var gpu: Double?
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var download: Double = 0
    @Published private(set) var upload: Double = 0
    @Published private(set) var battery: Double?
    @Published private(set) var diskUsed: Double = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    let gpuName = MTLCreateSystemDefaultDevice()?.name ?? "No Metal GPU"
    private var previousCPU: CPUSample?
    private var previousNetwork: (TNFNetworkBytes, Date)?
    private var timer: Timer?
    private var sampling = false
    private let queue = DispatchQueue(label: "ThisIsNotFree.telemetry", qos: .utility)

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; previousCPU = nil; previousNetwork = nil; hasNetworkInterval = false }
    deinit { timer?.invalidate() }

    private func sample() {
        guard !sampling else { return }
        sampling = true
        queue.async { [weak self] in
            var ticks = TNFCPUTicks()
            let validCPU = TNFReadCPUTicks(&ticks) != 0
            let cpu = CPUSample(busy: ticks.busy, idle: ticks.idle)
            let memory = TNFMemoryUsed()
            let gpu = TNFGPUUsage()
            let network = TNFReadNetworkBytes()
            let battery = TNFBatteryLevel()
            let disk = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let total = (disk?[.systemSize] as? NSNumber)?.doubleValue ?? 0
            let free = (disk?[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
            let date = Date()
            Task { @MainActor [weak self] in
                guard let self else { return }
                if validCPU {
                    self.cpu = self.previousCPU.flatMap { cpu.usage(since: $0) }
                    self.previousCPU = cpu
                }
                self.hasSample = true
                self.memoryUsed = memory
                self.gpu = gpu >= 0 ? gpu / 100 : nil
                self.battery = battery >= 0 ? battery : nil
                self.diskUsed = total > 0 ? (total - free) / total : 0
                if let previous = self.previousNetwork {
                    self.hasNetworkInterval = true
                    let seconds = max(date.timeIntervalSince(previous.1), 0.1)
                    self.download = network.received >= previous.0.received ? Double(network.received - previous.0.received) / seconds : 0
                    self.upload = network.sent >= previous.0.sent ? Double(network.sent - previous.0.sent) / seconds : 0
                }
                self.previousNetwork = (network, date)
                self.sampling = false
            }
        }
    }
}

@MainActor
final class AwakeController: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var endsAt: Date?
    @Published private(set) var error: String?
    private var assertion: UInt32 = 0
    private var timer: Timer?
    func start(minutes: Int) {
        stop()
        assertion = TNFKeepAwakeBegin()
        guard assertion != 0 else { error = "macOS could not create a keep-awake session."; return }
        error = nil
        active = true
        endsAt = minutes > 0 ? Date().addingTimeInterval(Double(minutes * 60)) : nil
        if minutes > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: Double(minutes * 60), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        TNFKeepAwakeEnd(assertion); assertion = 0
        active = false; endsAt = nil
    }
    deinit { timer?.invalidate(); TNFKeepAwakeEnd(assertion) }
}

struct DimmedDisplay: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    var brightness: Double
}

@MainActor
final class DisplayController: ObservableObject {
    @Published private(set) var displays: [DimmedDisplay] = []
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var observer: AnyCancellable?
    init() {
        refresh()
        observer = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func refresh() {
        let old = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.brightness) })
        displays = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            windows[id]?.setFrame(screen.frame, display: true)
            return DimmedDisplay(id: id, name: screen.localizedName, brightness: old[id] ?? 1)
        }
        let connected = Set(displays.map(\.id))
        for id in Set(windows.keys).subtracting(connected) { windows.removeValue(forKey: id)?.close() }
    }
    func setBrightness(_ value: Double, display: DimmedDisplay) {
        guard let index = displays.firstIndex(where: { $0.id == display.id }),
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == display.id }) else { return }
        let brightness = min(max(value, 0.2), 1)
        displays[index].brightness = brightness
        if brightness >= 0.999 { windows[display.id]?.orderOut(nil); return }
        let window: NSWindow
        if let existing = windows[display.id] { window = existing }
        else {
            window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
            window.isOpaque = false; window.hasShadow = false; window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            windows[display.id] = window
        }
        window.backgroundColor = .black.withAlphaComponent(1 - brightness)
        window.orderFrontRegardless()
    }
    func restoreAll() {
        for window in windows.values { window.orderOut(nil) }
        for index in displays.indices { displays[index].brightness = 1 }
    }
}

@MainActor
final class MenuBarTintController {
    private var windows: [UInt32: NSWindow] = [:]
    private var timer: Timer?
    private var color = NSColor.systemBlue
    private var strength: Double = 0.12
    func configure(enabled: Bool, color: NSColor, strength: Double) {
        self.color = color; self.strength = min(max(strength, 0), 0.22)
        guard enabled else { stop(); return }
        update()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.update() }
            }
        }
    }
    private func update() {
        var connected = Set<UInt32>()
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { continue }
            connected.insert(id)
            let topInset = screen.frame.maxY - screen.visibleFrame.maxY
            let height = topInset > 0 && topInset < 100 ? topInset : NSStatusBar.system.thickness
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
            let window: NSWindow
            if let existing = windows[id] { window = existing }
            else {
                window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isOpaque = false; window.hasShadow = false; window.ignoresMouseEvents = true
                window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                window.isReleasedWhenClosed = false
                windows[id] = window
            }
            window.setFrame(frame, display: true)
            window.backgroundColor = color.withAlphaComponent(strength)
            if NSMenu.menuBarVisible() && screen.frame.maxY - screen.visibleFrame.maxY >= height * 0.5 {
                window.orderFrontRegardless()
            } else { window.orderOut(nil) }
        }
        for id in Set(windows.keys).subtracting(connected) { windows.removeValue(forKey: id)?.close() }
    }
    func stop() { timer?.invalidate(); timer = nil; for window in windows.values { window.close() }; windows.removeAll() }
    deinit { timer?.invalidate() }
}
