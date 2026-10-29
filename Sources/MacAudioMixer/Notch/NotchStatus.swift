import Foundation
import CoreAudio
import CoreWLAN
import MixerCore

struct NotchBattery: Equatable, Identifiable {
    let id: String
    let name: String
    let level: Double
}

struct NotchStatus: Equatable {
    var wifiBars: Int?
    var wifiText = "Waiting for Wi-Fi status"
    var volume: Double?
    var batteries: [NotchBattery] = []

    static func read() -> NotchStatus {
        var result = NotchStatus()
        if let wifi = CWWiFiClient.shared().interface() {
            let rssi = wifi.rssiValue()
            if !wifi.powerOn() { result.wifiBars = 0; result.wifiText = "Wi-Fi off" }
            else if rssi < 0 {
                result.wifiBars = rssi > -60 ? 3 : rssi > -75 ? 2 : 1
                result.wifiText = "Wi-Fi signal: \(rssi) dBm"
            } else { result.wifiText = "Wi-Fi on · Signal unavailable" }
        } else { result.wifiText = "Wi-Fi unavailable" }
        let battery = TNFBatteryLevel()
        if battery >= 0 { result.batteries = [.init(id: "mac", name: "MacBook", level: min(1, battery))] }
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { return result }
        address = .init(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0; size = 4
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr, muted != 0 { result.volume = 0; return result }
        var values: [Double] = []
        for channel: UInt32 in [0, 1, 2] {
            address = .init(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: channel)
            var value: Float32 = 0; size = 4
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                values.append(Double(value)); if channel == 0 { break }
            }
        }
        if !values.isEmpty { result.volume = min(1, max(0, values.reduce(0, +) / Double(values.count))) }
        return result
    }
}

enum PeripheralBatteryReader {
    // system_profiler reports only the battery fields a connected device exposes.
    // Never infer a missing AirPods/case value or reuse a disconnected device.
    static func parse(_ data: Data) -> [NotchBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var result: [NotchBattery] = []
        let fields = [("device_batteryLevelMain", ""), ("device_batteryLevelLeft", "Left"),
                      ("device_batteryLevelRight", "Right"), ("device_batteryLevelCase", "Case"),
                      ("device_batteryLevel", "")]
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry.sorted(by: { $0.key < $1.key }) {
                    guard let device = value as? [String: Any] else { continue }
                    let address = device["device_address"] as? String ?? name
                    for (key, suffix) in fields {
                        guard let raw = device[key] else { continue }
                        let number = (raw as? NSNumber)?.doubleValue ?? Double((raw as? String ?? "").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
                        guard let number, number.isFinite, (0...100).contains(number) else { continue }
                        let id = address + ":" + suffix
                        guard !result.contains(where: { $0.id == id }) else { continue }
                        result.append(.init(id: id, name: suffix.isEmpty ? name : name + " · " + suffix, level: number / 100))
                    }
                }
            }
        }
        return result.sorted { $0.id < $1.id }
    }
}
