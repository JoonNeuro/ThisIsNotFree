import XCTest
@testable import MacAudioMixer

final class LayoutTests: XCTestCase {
    @MainActor
    func testLayoutPresetsAndMixedPlacementsPersist() {
        let name = "ThisIsNotFree.LayoutTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = HubPreferences(defaults: defaults)
        preferences.modules = ["audio", "storage", "awake", "shelf"]
        preferences.setupComplete = true
        preferences.workspaceConfigured = true
        preferences.applyLayout(.box)
        XCTAssertTrue(preferences.showsBox)
        XCTAssertEqual(Set(preferences.boxModules), [.audio, .storage, .awake, .shelf])
        XCTAssertTrue(preferences.menuBarModules.isEmpty)
        XCTAssertTrue(preferences.externalInBox)
        XCTAssertFalse(preferences.showsCustomGroups)

        preferences.applyLayout(.individual)
        XCTAssertFalse(preferences.showsBox)
        XCTAssertEqual(Set(preferences.menuBarModules), [.audio, .storage, .awake, .shelf])
        XCTAssertFalse(preferences.externalInBox)
        preferences.setPlacement(.storage, .box)
        preferences.setPlacement(.awake, .window)
        preferences.includeAllExternal = false
        XCTAssertEqual(preferences.layout, .custom)
        XCTAssertTrue(preferences.showsBox)
        XCTAssertEqual(preferences.boxModules, [.storage])
        XCTAssertEqual(Set(preferences.menuBarModules), [.audio, .shelf])
        XCTAssertTrue(preferences.showsCustomGroups)

        let restored = HubPreferences(defaults: defaults)
        XCTAssertTrue(restored.workspaceConfigured)
        XCTAssertEqual(restored.layout, .custom)
        XCTAssertEqual(restored.placement(.storage), .box)
        XCTAssertEqual(restored.placement(.awake), .window)
        XCTAssertFalse(restored.includeAllExternal)
        XCTAssertEqual(restored.modules, preferences.modules)
        restored.applyLayout(.window)
        XCTAssertFalse(restored.showsBox)
        XCTAssertTrue(restored.menuBarModules.isEmpty)
        XCTAssertFalse(restored.showsCustomGroups)
        XCTAssertEqual(restored.modules, preferences.modules, "Layout must not disable a tool's app-window access")
    }

    @MainActor
    func testOnlyEnabledToolsReceiveIconsAndMigrationKeepsChoices() {
        let name = "ThisIsNotFree.LayoutTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["audio", "storage"], forKey: "hub.modules")
        defaults.set(true, forKey: "hub.setupComplete")
        let preferences = HubPreferences(defaults: defaults)
        XCTAssertEqual(preferences.modules, ["audio", "storage"])
        XCTAssertFalse(preferences.workspaceConfigured, "Existing users should see the new layout setup")
        preferences.applyLayout(.individual)
        XCTAssertTrue(preferences.menuBarModules.isEmpty, "Setup must finish before scattering icons")
        preferences.workspaceConfigured = true
        XCTAssertEqual(Set(preferences.menuBarModules), [.audio, .storage])
        preferences.set(.storage, enabled: false)
        XCTAssertEqual(preferences.menuBarModules, [.audio])
        preferences.setPlacement(.shelf, .box)
        XCTAssertTrue(preferences.boxModules.isEmpty, "A disabled tool must not appear in the box")
    }
}
