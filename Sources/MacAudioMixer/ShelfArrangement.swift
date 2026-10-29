import Foundation

enum ShelfDestination: String, Codable, CaseIterable, Identifiable {
    case shelf, keep, hidden
    var id: String { rawValue }
    var title: String { switch self { case .shelf: return "In Shelf"; case .keep: return "Keep in Menu Bar"; case .hidden: return "Hidden" } }
    var detail: String {
        switch self {
        case .shelf: return "Shown in the horizontal bar; originals can be collapsed."
        case .keep: return "Keep the original visible; omit it from the Shelf."
        case .hidden: return "Omit from the Shelf and collapse the original after applying."
        }
    }
}

struct ShelfArrangement: Codable, Equatable {
    var destinations: [String: ShelfDestination] = [:]
    var order: [String] = []
    func destination(_ id: String) -> ShelfDestination { destinations[id] ?? .keep }
    mutating func assign(_ id: String, to destination: ShelfDestination, before: String? = nil) {
        destinations[id] = destination
        order.removeAll { $0 == id }
        if let before, let index = order.firstIndex(of: before) { order.insert(id, at: index) }
        else { order.append(id) }
    }
    func ordered(_ items: [ShelfItem]) -> [ShelfItem] {
        let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return items.enumerated().sorted {
            let a = ranks[$0.element.id] ?? (order.count + $0.offset)
            let b = ranks[$1.element.id] ?? (order.count + $1.offset)
            return a < b
        }.map(\.element)
    }
    static func load(defaults: UserDefaults = .standard) -> ShelfArrangement {
        if let data = defaults.data(forKey: "shelf.arrangement"), let value = try? JSONDecoder().decode(Self.self, from: data) { return value }
        var value = Self()
        for id in defaults.stringArray(forKey: "shelf.pinned") ?? [] { value.assign(id, to: .shelf) }
        return value
    }
    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "shelf.arrangement") }
    }
}
