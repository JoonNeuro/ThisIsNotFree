import AppKit
import CoreAudio
import Darwin
import MixerCore

struct AudioSource {
    let processObjectID: AudioObjectID
    let sourceDeviceID: AudioObjectID
}

struct AudioApp: Identifiable {
    let id: String
    let sources: [AudioSource]
    let name: String
    let bundleID: String?
    let icon: NSImage?
    var volume: Double
}

struct OutputDevice: Identifiable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let supportsHardwareVolume: Bool
    let isDefault: Bool
    var volume: Double
}

@MainActor
final class MixerModel: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var outputDevices: [OutputDevice] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var outputName = "Default Output"
    @Published private(set) var requestingPermission = false

    let readOnly: Bool
    private let engine = TapEngine()
    private var timer: Timer?
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var outputDeviceID: AudioObjectID = 0
    private var preferredVolumes: [String: Double] = UserDefaults.standard.dictionary(forKey: "appVolumes") as? [String: Double] ?? [:]
    private var softwareDeviceVolumes: [String: Double] = UserDefaults.standard.dictionary(forKey: "softwareDeviceVolumes") as? [String: Double] ?? [:]
    private var preferredRoutes: [String: String] = UserDefaults.standard.dictionary(forKey: "appOutputDevices") as? [String: String] ?? [:]
    private var preparedProcesses: [ProcessEntry] = []

    init(readOnly: Bool = false) {
        self.readOnly = readOnly
        installProcessListListener()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if !readOnly { requestPermission() }
    }

    deinit {
        timer?.invalidate()
        if let processListListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                      mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                                    &address, DispatchQueue.main, processListListener)
        }
    }

    private func installProcessListListener() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.prepareSavedProcesses()
                self?.refresh()
            }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &address, DispatchQueue.main, listener) == noErr {
            processListListener = listener
        }
    }

    private func prepareSavedProcesses() {
        guard !readOnly else { return }
        guard preferredVolumes.values.contains(where: { $0 < 1 }) || !preferredRoutes.isEmpty ||
                outputDevices.contains(where: { !$0.supportsHardwareVolume && $0.volume < 1 }) else { return }
        let known = Set(preparedProcesses.map(\.objectID))
        let system = AudioObjectID(kAudioObjectSystemObject)
        for id in Self.objectIDs(object: system, selector: kAudioHardwarePropertyProcessObjectList) where !known.contains(id) {
            guard let pid: pid_t = Self.property(object: id, selector: kAudioProcessPropertyPID, initial: 0),
                  pid != ProcessInfo.processInfo.processIdentifier else { continue }
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let executableURL = Self.executableBundleURL(pid: pid)
            let bundleID = Self.processBundleID(id: id,
                                                 runningApp: runningApp, executableURL: executableURL)
            let key = bundleID ?? "pid:\(pid)"
            let devices = Self.objectIDs(object: id, selector: kAudioProcessPropertyDevices,
                                         scope: kAudioDevicePropertyScopeOutput)
            let source = devices.contains(outputDeviceID) ? outputDeviceID : (devices.first ?? outputDeviceID)
            let target = routedDevice(for: key, original: source)
            let gain = preferredVolumes[key] ?? 1
            guard gain < 1 || preferredRoutes[key] != nil || softwareGain(for: target) < 1 else { continue }
            engine.set(processID: id, volume: Float(gain * softwareGain(for: target)),
                       source: source, target: target, retry: false) { [weak self] status in
                guard status != noErr else { return }
                Task { @MainActor [weak self] in
                    self?.errorMessage = "Could not prepare \(key) audio (Core Audio \(status))."
                }
            }
        }
    }

    func volume(for app: AudioApp) -> Double { apps.first(where: { $0.id == app.id })?.volume ?? app.volume }

    func setVolume(_ value: Double, for app: AudioApp) {
        guard !readOnly else { return }
        let clamped = min(max(value, 0), 1)
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].volume = clamped
        preferredVolumes[app.id] = clamped
        UserDefaults.standard.set(preferredVolumes, forKey: "appVolumes")
        errorMessage = nil
        for source in apps[index].sources {
            let target = targetDevice(for: apps[index], source: source)
            engine.set(processID: source.processObjectID,
                       volume: Float(clamped * softwareGain(for: target)),
                       source: source.sourceDeviceID, target: target, retry: true) { [weak self] status in
                guard status != noErr else { return }
                Task { @MainActor [weak self] in
                    self?.errorMessage = "Could not connect \(app.name) to Core Audio (\(status)). Check System Audio Recording permission and the output device."
                }
            }
        }
    }

    func dismissError() { errorMessage = nil }

    func outputSelection(for app: AudioApp) -> String { preferredRoutes[app.id] ?? "" }

    func setOutputDevice(_ uid: String, for app: AudioApp) {
        guard !readOnly else { return }
        guard let current = apps.first(where: { $0.id == app.id }) else { return }
        if uid.isEmpty {
            preferredRoutes.removeValue(forKey: app.id)
        } else {
            guard outputDevices.contains(where: { $0.uid == uid }) else { return }
            preferredRoutes[app.id] = uid
        }
        UserDefaults.standard.set(preferredRoutes, forKey: "appOutputDevices")
        errorMessage = nil
        for source in current.sources {
            let target = targetDevice(for: current, source: source)
            engine.set(processID: source.processObjectID,
                       volume: Float(current.volume * softwareGain(for: target)),
                       source: source.sourceDeviceID, target: target, retry: true) { [weak self] status in
                guard status != noErr else { return }
                Task { @MainActor [weak self] in
                    self?.errorMessage = "Could not route \(current.name) to the selected output (Core Audio \(status))."
                }
            }
        }
    }

    private func targetDevice(for app: AudioApp, source: AudioSource) -> AudioObjectID {
        routedDevice(for: app.id, original: source.sourceDeviceID)
    }

    private func routedDevice(for appID: String, original: AudioObjectID) -> AudioObjectID {
        guard let uid = preferredRoutes[appID],
              let device = outputDevices.first(where: { $0.uid == uid }) else { return original }
        return device.id
    }

    func outputVolume(for device: OutputDevice) -> Double {
        outputDevices.first(where: { $0.id == device.id })?.volume ?? device.volume
    }

    func setOutputVolume(_ value: Double, for device: OutputDevice) {
        guard !readOnly else { return }
        let clamped = min(max(value, 0), 1)
        guard let index = outputDevices.firstIndex(where: { $0.id == device.id }) else { return }
        let crossedFullVolume = (outputDevices[index].volume == 1) != (clamped == 1)
        if device.supportsHardwareVolume {
            let status = Self.setHardwareVolume(device.id, Float(clamped))
            guard status == noErr else {
                errorMessage = "Could not set \(device.name) volume (Core Audio \(status))."
                return
            }
        } else {
            softwareDeviceVolumes[device.uid] = clamped
            UserDefaults.standard.set(softwareDeviceVolumes, forKey: "softwareDeviceVolumes")
        }
        outputDevices[index].volume = clamped
        for entry in preparedProcesses where routedDevice(for: entry.key, original: entry.outputDeviceID) == device.id {
            let appVolume = apps.first(where: { $0.id == entry.key })?.volume ?? preferredVolumes[entry.key] ?? 1
            engine.set(processID: entry.objectID,
                       volume: Float(appVolume * softwareGain(for: device.id)),
                       source: entry.outputDeviceID, target: device.id, retry: false) { [weak self] status in
                guard status != noErr else { return }
                Task { @MainActor [weak self] in
                    self?.errorMessage = "Could not adjust \(device.name) audio (Core Audio \(status))."
                }
            }
        }
        if !device.supportsHardwareVolume && crossedFullVolume { refresh() }
    }

    private func softwareGain(for deviceID: AudioObjectID) -> Double {
        guard let device = outputDevices.first(where: { $0.id == deviceID }),
              !device.supportsHardwareVolume else { return 1 }
        return device.volume
    }

    func requestPermission() {
        guard !readOnly else { return }
        guard outputDeviceID != 0, !requestingPermission else { return }
        requestingPermission = true
        engine.requestPermission(output: outputDeviceID) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.requestingPermission = false
                if status != noErr {
                    self?.errorMessage = "Could not request audio permission (Core Audio \(status)). Open System Settings below and add this app."
                } else {
                    self?.errorMessage = nil
                }
                self?.refresh(retryFailed: true)
            }
        }
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh(retryFailed: Bool = false) {
        let device = Self.defaultOutputDevice()
        outputDeviceID = device
        outputName = Self.deviceName(device) ?? "Default Output"
        outputDevices = Self.availableOutputDevices(defaultOutput: device, softwareVolumes: softwareDeviceVolumes)
        let previous = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0.volume) })
        let processes = Self.audioProcesses(defaultOutput: device)
        let grouped = Dictionary(grouping: processes.filter(\.isRunningOutput), by: \.key)
        let found = grouped.map { key, entries -> AudioApp in
            let first = entries[0]
            return AudioApp(id: key, sources: entries.map { AudioSource(processObjectID: $0.objectID,
                                                                        sourceDeviceID: $0.outputDeviceID) },
                            name: first.name, bundleID: first.bundleID, icon: first.icon,
                            volume: previous[key] ?? preferredVolumes[key] ?? 1)
        }
        apps = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !readOnly else { return }
        let activeVolumes = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0.volume) })
        let prepared = processes.filter { entry in
            let target = routedDevice(for: entry.key, original: entry.outputDeviceID)
            return entry.isRunningOutput || preferredRoutes[entry.key] != nil ||
                (preferredVolumes[entry.key] ?? 1) < 1 || softwareGain(for: target) < 1
        }
        preparedProcesses = prepared
        engine.removeProcesses(except: Set(prepared.map(\.objectID)))
        // Keep saved app and software-device gains installed while playback is idle.
        for entry in prepared {
            let target = routedDevice(for: entry.key, original: entry.outputDeviceID)
            let gain = activeVolumes[entry.key] ?? preferredVolumes[entry.key] ?? 1
            engine.set(processID: entry.objectID,
                       volume: Float(gain * softwareGain(for: target)),
                       source: entry.outputDeviceID, target: target, retry: retryFailed) { [weak self] status in
                guard status != noErr else { return }
                Task { @MainActor [weak self] in
                    self?.errorMessage = "Could not connect \(entry.name) to Core Audio (\(status)). Check System Audio Recording permission and the output device."
                }
            }
        }
    }

    private static func property<T: FixedWidthInteger>(object: AudioObjectID, selector: AudioObjectPropertySelector,
                                                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                                        initial: T) -> T? {
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                  mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        property(object: AudioObjectID(kAudioObjectSystemObject),
                 selector: kAudioHardwarePropertyDefaultOutputDevice,
                 initial: AudioObjectID(0)) ?? 0
    }

    private static func deviceName(_ id: AudioObjectID) -> String? {
        guard id != 0 else { return nil }
        var name: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return name as String?
    }

    private static func volumeElements(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        func writable(_ element: AudioObjectPropertyElement) -> Bool {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                      mScope: kAudioDevicePropertyScopeOutput,
                                                      mElement: element)
            guard AudioObjectHasProperty(device, &address) else { return false }
            var canSet: DarwinBoolean = false
            return AudioObjectIsPropertySettable(device, &address, &canSet) == noErr && canSet.boolValue
        }
        if writable(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        return (1...16).map { AudioObjectPropertyElement($0) }.filter(writable)
    }

    private static func hardwareVolume(_ device: AudioObjectID, elements: [AudioObjectPropertyElement]) -> Double? {
        let values: [Float] = elements.compactMap { element in
            var value: Float = 0
            var size = UInt32(MemoryLayout<Float>.size)
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                      mScope: kAudioDevicePropertyScopeOutput,
                                                      mElement: element)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
        }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func setHardwareVolume(_ device: AudioObjectID, _ volume: Float) -> OSStatus {
        let elements = volumeElements(device)
        guard !elements.isEmpty else { return kAudioHardwareUnsupportedOperationError }
        for element in elements {
            var value = volume
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                      mScope: kAudioDevicePropertyScopeOutput,
                                                      mElement: element)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil,
                                                    UInt32(MemoryLayout<Float>.size), &value)
            if status != noErr { return status }
        }
        return noErr
    }

    private static func availableOutputDevices(defaultOutput: AudioObjectID,
                                               softwareVolumes: [String: Double]) -> [OutputDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        return objectIDs(object: system, selector: kAudioHardwarePropertyDevices).compactMap { id in
            let streams = objectIDs(object: id, selector: kAudioDevicePropertyStreams,
                                    scope: kAudioDevicePropertyScopeOutput)
            guard !streams.isEmpty, deviceName(id) != "MacAudioMixer private output" else { return nil }
            let uid = stringProperty(object: id, selector: kAudioDevicePropertyDeviceUID) ?? "device:\(id)"
            let elements = volumeElements(id)
            let hardware = !elements.isEmpty
            let volume = hardware ? (hardwareVolume(id, elements: elements) ?? 1)
                                  : (softwareVolumes[uid] ?? 1)
            return OutputDevice(id: id, uid: uid, name: deviceName(id) ?? "Output \(id)",
                                supportsHardwareVolume: hardware, isDefault: id == defaultOutput,
                                volume: min(max(volume, 0), 1))
        }
        .sorted { left, right in
            if left.isDefault != right.isDefault { return left.isDefault }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private struct ProcessEntry {
        let objectID: AudioObjectID
        let pid: pid_t
        let key: String
        let name: String
        let bundleID: String?
        let icon: NSImage?
        let outputDeviceID: AudioObjectID
        let isRunningOutput: Bool
    }

    private static func objectIDs(object: AudioObjectID, selector: AudioObjectPropertySelector,
                                  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                  mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func stringProperty(object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func executableBundleURL(pid: pid_t) -> URL? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        let components = NSString(string: path).pathComponents
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components[...appIndex])))
    }

    private static let installedApps: [String: URL] = {
        let roots = ["/System/Applications", "/System/Applications/Utilities", "/Applications",
                     NSHomeDirectory() + "/Applications"]
        var found: [String: URL] = [:]
        for root in roots {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: root),
                                                                          includingPropertiesForKeys: nil) else { continue }
            for url in urls where url.pathExtension == "app" {
                if let id = Bundle(url: url)?.bundleIdentifier { found[id] = url }
            }
        }
        return found
    }()

    private static func appIcon(bundle: Bundle?, appURL: URL?, runningApp: NSRunningApplication?) -> NSImage? {
        if let bundle,
           let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            let fileName = iconName.hasSuffix(".icns") ? iconName : iconName + ".icns"
            let iconURL = bundle.resourceURL?.appendingPathComponent(fileName)
            if let iconURL, let image = NSImage(contentsOf: iconURL) { return image }
        }
        return runningApp?.icon ?? appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private static func processBundleID(id: AudioObjectID,
                                        runningApp: NSRunningApplication?, executableURL: URL?) -> String? {
        let coreBundleID = stringProperty(object: id, selector: kAudioProcessPropertyBundleID)
        let executableBundleID = executableURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        return (executableBundleID != "com.apple.Terminal" ? executableBundleID : nil)
            ?? coreBundleID
            ?? executableBundleID
            ?? runningApp?.bundleIdentifier
    }

    private static func audioProcesses(defaultOutput: AudioObjectID) -> [ProcessEntry] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let ids = objectIDs(object: system, selector: kAudioHardwarePropertyProcessObjectList)
        return ids.compactMap { id in
            guard let pid: pid_t = property(object: id, selector: kAudioProcessPropertyPID, initial: 0),
                  pid != ProcessInfo.processInfo.processIdentifier else { return nil }
            let running: UInt32 = property(object: id, selector: kAudioProcessPropertyIsRunningOutput, initial: 0) ?? 0
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let executableURL = executableBundleURL(pid: pid)
            let bundleID = processBundleID(id: id,
                                           runningApp: runningApp, executableURL: executableURL)
            let matchingRunningApp = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
            let appURL = bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                ?? matchingRunningApp?.bundleURL
                ?? bundleID.flatMap { installedApps[$0] }
                ?? executableURL
            let bundle = appURL.flatMap(Bundle.init(url:))
            let name = bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.infoDictionary?["CFBundleName"] as? String
                ?? bundleID
                ?? runningApp?.localizedName
                ?? "Process \(pid)"
            let icon = appIcon(bundle: bundle, appURL: appURL,
                               runningApp: matchingRunningApp ?? runningApp)
            let devices = objectIDs(object: id, selector: kAudioProcessPropertyDevices,
                                    scope: kAudioDevicePropertyScopeOutput)
            let selectedDevice = devices.contains(defaultOutput) ? defaultOutput : (devices.first ?? defaultOutput)
            return ProcessEntry(objectID: id, pid: pid, key: bundleID ?? "pid:\(pid)",
                                name: name, bundleID: bundleID, icon: icon,
                                outputDeviceID: selectedDevice, isRunningOutput: running != 0)
        }
    }
}

// All tap creation and destruction happens on one queue, away from the UI thread.
private final class TapEngine {
    private struct ActiveTap {
        let pointer: OpaquePointer
        let source: AudioObjectID
        let target: AudioObjectID
    }
    private struct DesiredTap {
        let volume: Float
        let source: AudioObjectID
        let target: AudioObjectID
    }
    private let queue = DispatchQueue(label: "com.macaudiomixer.audio")
    private var taps: [AudioObjectID: ActiveTap] = [:]
    private var desired: [AudioObjectID: DesiredTap] = [:]
    private var failed: Set<AudioObjectID> = []

    func requestPermission(output: AudioObjectID, completion: @escaping (OSStatus) -> Void) {
        queue.async { completion(MixerTapRequestPermission(output)) }
    }

    func set(processID: AudioObjectID, volume: Float, source: AudioObjectID,
             target: AudioObjectID, retry: Bool,
             onError: @escaping (OSStatus) -> Void) {
        queue.async { [self] in
            let previous = desired[processID]
            desired[processID] = DesiredTap(volume: volume, source: source, target: target)
            if source == 0 || target == 0 {
                if let tap = taps.removeValue(forKey: processID) { MixerTapDestroy(tap.pointer) }
                failed.remove(processID)
                return
            }
            if let tap = taps[processID] {
                if tap.source == source && tap.target == target {
                    MixerTapSetVolume(tap.pointer, volume)
                    return
                }
                MixerTapDestroy(tap.pointer)
                taps.removeValue(forKey: processID)
                failed.remove(processID)
            }
            if retry || previous?.source != source || previous?.target != target { failed.remove(processID) }
            if failed.contains(processID) { return }
            var status: OSStatus = noErr
            if let tap = MixerTapCreate(processID, source, target, volume, &status) {
                taps[processID] = ActiveTap(pointer: tap, source: source, target: target)
            } else {
                failed.insert(processID)
                onError(status)
            }
        }
    }

    func removeProcesses(except active: Set<AudioObjectID>) {
        queue.async { [self] in
            for id in Set(desired.keys).subtracting(active) {
                desired.removeValue(forKey: id)
                failed.remove(id)
                if let tap = taps.removeValue(forKey: id) { MixerTapDestroy(tap.pointer) }
            }
        }
    }

    deinit {
        queue.sync { for tap in taps.values { MixerTapDestroy(tap.pointer) } }
    }
}
