import AppKit
import Combine

@MainActor
final class NotchHubController: ObservableObject {
    @Published private(set) var status = NotchStatus()
    @Published private(set) var screenName: String?
    @Published private(set) var geometry: NotchGeometry?
    @Published private(set) var enabled = false
    @Published var calibration: NotchCalibration { didSet {
        if let data = try? JSONEncoder().encode(calibration) { defaults.set(data, forKey: "notch.calibration") }
        updateScreens()
    } }
    private let defaults: UserDefaults
    private let shelf: MenuShelf
    private var previewVisible = false
    private var panels: [NSPanel] = []
    private var timer: Timer?
    private var mouseTimer: Timer?
    private var observers = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "ThisIsNotFree.notch.status", qos: .utility)
    private var sampling = false
    private var peripheralBatteries: [NotchBattery] = []
    private var nextPeripheralRead = Date.distantPast
    private var peripheralProcess: Process?
    private var peripheralTimeout: DispatchWorkItem?
    private var generation = UUID()

    init(shelf: MenuShelf, defaults: UserDefaults = .standard) {
        self.shelf = shelf; self.defaults = defaults
        calibration = defaults.data(forKey: "notch.calibration").flatMap { try? JSONDecoder().decode(NotchCalibration.self, from: $0) } ?? .init()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.updateScreens() } }.store(in: &observers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.updateScreens(); self?.sample() } }.store(in: &observers)
        updateScreens()
    }
    func start() {
        guard !enabled else { return }
        enabled = true; updateScreens(); updateSampling()
    }
    func stop() {
        if enabled { enabled = false; closePanels() }
        updateSampling()
    }
    func shutdown() { previewVisible = false; stop() }
    func setPreviewVisible(_ visible: Bool) {
        guard visible != previewVisible else { return }
        previewVisible = visible; updateSampling()
    }
    func open(_ zone: NotchZone) { shelf.openSystemMenu(zone, preferredID: calibration.menuItems[zone.rawValue]) }
    func resetCalibration() {
        var reset = NotchCalibration(); reset.menuItems = calibration.menuItems
        calibration = reset
    }

    private func updateSampling() {
        if enabled || previewVisible {
            guard timer == nil else { return }
            sample()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sample() }
            }
        } else {
            timer?.invalidate(); timer = nil
            generation = UUID()
            peripheralTimeout?.cancel(); peripheralTimeout = nil
            if let process = peripheralProcess, process.isRunning { process.terminate() }
            peripheralProcess = nil
            peripheralBatteries = []; nextPeripheralRead = .distantPast
        }
    }
    private func sample() {
        guard (enabled || previewVisible), !sampling else { return }
        sampling = true
        queue.async { [weak self] in
            let snapshot = NotchStatus.read()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sampling = false
                guard self.enabled || self.previewVisible else { return }
                var merged = snapshot; merged.batteries += self.peripheralBatteries
                self.status = merged
                self.redraw()
            }
        }
        if Date() >= nextPeripheralRead, peripheralProcess == nil { readPeripherals() }
    }
    private func readPeripherals() {
        nextPeripheralRead = Date().addingTimeInterval(60)
        let process = Process(), pipe = Pipe(), token = generation
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "full"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
        peripheralProcess = process
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        peripheralTimeout = timeout
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: timeout)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let batteries = process.terminationStatus == 0 ? PeripheralBatteryReader.parse(data) : []
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.peripheralTimeout?.cancel()
                self.peripheralProcess = nil; self.peripheralTimeout = nil
                self.peripheralBatteries = batteries
                self.status.batteries = self.status.batteries.filter { $0.id == "mac" } + batteries
                self.redraw()
            }
        }
    }
    private func closePanels() {
        mouseTimer?.invalidate(); mouseTimer = nil
        panels.forEach { $0.orderOut(nil); $0.close() }; panels = []
    }
    private func updateScreens() {
        closePanels()
        let screens = NSScreen.screens.filter { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }
        screenName = screens.first?.localizedName
        geometry = screens.first.flatMap { measuredGeometry($0) }
        guard enabled else { return }
        for screen in screens {
            guard let geometry = measuredGeometry(screen), let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { continue }
            let center = (left.maxX + right.minX) / 2
            let rect = NSRect(x: center - geometry.width/2 - geometry.padding, y: screen.frame.maxY - geometry.size.height,
                              width: geometry.size.width, height: geometry.size.height)
            let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.backgroundColor = .clear; panel.isOpaque = false
            panel.hasShadow = false; panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
            let view = NotchEdgeView(frame: NSRect(origin: .zero, size: geometry.size))
            view.geometry = geometry; view.status = status
            view.toolTip = edgeDescription
            view.onActivate = { [weak self] zone in self?.open(zone) }
            panel.contentView = view; panel.orderFrontRegardless(); panels.append(panel)
        }
        if !panels.isEmpty {
            // Keep the whole transparent camera rectangle click-through. Only a
            // six-point corridor around a painted edge receives mouse events.
            mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateHitRegions() }
            }
        }
    }
    private func measuredGeometry(_ screen: NSScreen) -> NotchGeometry? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        let width = max(60, right.minX - left.maxX + calibration.widthAdjustment)
        let height = max(12, screen.safeAreaInsets.top + calibration.heightAdjustment)
        return .init(width: width, height: height, calibration: calibration)
    }
    private func updateHitRegions() {
        for panel in panels {
            guard let view = panel.contentView as? NotchEdgeView, let geometry = view.geometry else { continue }
            let point = view.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            panel.ignoresMouseEvents = geometry.zone(at: point) == nil
        }
    }
    private func redraw() {
        panels.forEach { panel in
            if let view = panel.contentView as? NotchEdgeView { view.status = status; view.toolTip = edgeDescription; view.needsDisplay = true }
        }
    }
    private var edgeDescription: String {
        ([status.wifiText, status.volume.map { "Sound \(Int(($0 * 100).rounded()))%" } ?? "Sound level unavailable"] +
         status.batteries.map { "\($0.name) \(Int(($0.level * 100).rounded()))%" } + ["Click an edge to open its original system menu."]).joined(separator: "\n")
    }
}
