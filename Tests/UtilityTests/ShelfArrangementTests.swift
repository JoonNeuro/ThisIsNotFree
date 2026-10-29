import XCTest
import ApplicationServices
@testable import MacAudioMixer

final class ShelfArrangementTests: XCTestCase {
    private func item(_ id: String) -> ShelfItem {
        .init(id: id, title: id, appName: "Test", icon: nil, element: AXUIElementCreateSystemWide())
    }
    func testDestinationsAndDragOrderPersistWithoutLosingUnavailableItems() {
        let suite = "ThisIsNotFree.ShelfTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var model = ShelfArrangement()
        model.order = ["a", "b", "c"]
        model.assign("c", to: .shelf, before: "a")
        model.assign("b", to: .hidden)
        model.assign("a", to: .keep)
        XCTAssertEqual(model.destination("b"), .hidden)
        XCTAssertEqual(model.destination("a"), .keep)
        XCTAssertEqual(model.destination("new"), .keep)
        XCTAssertEqual(model.ordered([item("a"), item("c"), item("new")]).map(\.id), ["c", "a", "new"])
        model.save(defaults: defaults)
        let restored = ShelfArrangement.load(defaults: defaults)
        XCTAssertEqual(restored, model)
        XCTAssertEqual(restored.destination("b"), .hidden, "Disconnected items must retain their choice")
        defaults.removeObject(forKey: "shelf.arrangement")
    }
    @MainActor
    func testAssignBeforeUnrankedItemUsesCurrentInventoryOrder() {
        // The model seeds all inventory IDs before applying a drop. Exercise the
        // same pure arrangement operation without posting UI input or hiding icons.
        var arrangement = ShelfArrangement()
        let inventory = [item("a"), item("b"), item("c")]
        arrangement.order = arrangement.ordered(inventory).map(\.id)
        arrangement.assign("c", to: .shelf, before: "b")
        XCTAssertEqual(arrangement.ordered(inventory).map(\.id), ["a", "c", "b"])
    }
}
