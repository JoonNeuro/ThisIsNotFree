import Foundation
import CoreWLAN

struct ToolGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var symbol: String
    var members: [String]
    var showInMenuBar: Bool
    static let builtIns: [(id: String, name: String)] = [
        ("system:wifi", "Wi-Fi"), ("system:battery", "Battery"),
        ("tool:system", "System Monitor"), ("tool:audio", "Audio Outputs"),
        ("tool:storage", "Storage Tracker"), ("tool:awake", "Keep Awake"), ("tool:displays", "Display Dimming")
    ]
    static let symbols = ["square.grid.2x2.fill", "tray.full.fill", "bolt.fill", "star.fill", "circle.grid.2x2.fill", "laptopcomputer", "network"]
}

@MainActor
final class ToolGroups: ObservableObject {
    @Published private(set) var groups: [ToolGroup] {
        didSet { if let data = try? JSONEncoder().encode(groups) { defaults.set(data, forKey: "hub.groups") } }
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "hub.groups"), let decoded = try? JSONDecoder().decode([ToolGroup].self, from: data) {
            groups = decoded
        } else {
            groups = [.init(id: UUID(), name: "Essentials", symbol: "square.grid.2x2.fill",
                            members: ["system:wifi", "system:battery", "tool:audio", "tool:awake"], showInMenuBar: false)]
        }
    }
    @discardableResult func add() -> UUID {
        let group = ToolGroup(id: UUID(), name: "New Group", symbol: ToolGroup.symbols[0], members: [], showInMenuBar: false)
        groups.append(group)
        return group.id
    }
    func update(_ id: UUID, _ transform: (inout ToolGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        var group = groups[index]; transform(&group); groups[index] = group
    }
    func remove(_ id: UUID) { groups.removeAll { $0.id == id } }
    func toggleMember(_ member: String, group id: UUID) {
        update(id) { group in
            if group.members.contains(member) { group.members.removeAll { $0 == member } } else { group.members.append(member) }
        }
    }
    func moveMember(_ member: String, group id: UUID, offset: Int) {
        update(id) { group in
            guard let index = group.members.firstIndex(of: member), group.members.indices.contains(index + offset) else { return }
            group.members.swapAt(index, index + offset)
        }
    }
}

@MainActor
final class WiFiController: ObservableObject {
    @Published private(set) var powered: Bool?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private var refreshing = false
    private let queue = DispatchQueue(label: "ThisIsNotFree.wifi", qos: .userInitiated)
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        queue.async { [weak self] in
            let value = CWWiFiClient.shared().interface()?.powerOn()
            Task { @MainActor [weak self] in self?.powered = value; self?.refreshing = false }
        }
    }
    func toggle() {
        guard !busy else { return }
        busy = true
        queue.async { [weak self] in
            var message: String?
            let interface = CWWiFiClient.shared().interface()
            do {
                guard let interface else { throw NSError(domain: "WiFiUnavailable", code: 1) }
                try interface.setPower(!interface.powerOn())
            } catch { message = "Wi-Fi could not be changed. Use Control Center or System Settings." }
            let value = interface?.powerOn()
            Task { @MainActor [weak self] in self?.powered = value; self?.busy = false; self?.error = message }
        }
    }
}
