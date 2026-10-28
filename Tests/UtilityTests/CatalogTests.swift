import XCTest
@testable import MacAudioMixer

final class CatalogTests: XCTestCase {
    func testEveryToolAppearsExactlyOnceAcrossCategories() {
        let tools = ToolCategory.allCases.flatMap(\.modules)
        XCTAssertEqual(Set(tools), Set(UtilityModule.allCases))
        XCTAssertEqual(tools.count, UtilityModule.allCases.count)
        XCTAssertTrue(UtilityModule.allCases.allSatisfy { !$0.features.isEmpty })
    }

    @MainActor
    func testFreshCatalogDoesNotEnableServicesUntilToolIsAdded() {
        let name = "ThisIsNotFree.CatalogTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = HubPreferences(defaults: defaults)
        XCTAssertTrue(preferences.modules.isEmpty)
        XCTAssertFalse(preferences.setupComplete)
        preferences.activate(.storage)
        XCTAssertTrue(preferences.setupComplete)
        XCTAssertTrue(preferences.workspaceConfigured)
        XCTAssertEqual(preferences.modules, ["storage"])
        XCTAssertEqual(preferences.boxModules, [.storage])
        preferences.set(.storage, enabled: false)
        XCTAssertTrue(preferences.boxModules.isEmpty)
        XCTAssertTrue(preferences.modules.isEmpty)
        XCTAssertTrue(preferences.setupComplete)
        let restored = HubPreferences(defaults: defaults)
        XCTAssertTrue(restored.setupComplete)
        XCTAssertTrue(restored.modules.isEmpty)
    }
}
