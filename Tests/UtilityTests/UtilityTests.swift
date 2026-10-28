import XCTest
@testable import MacAudioMixer

final class UtilityTests: XCTestCase {
    func testReleaseVersionsCompareNumerically() {
        XCTAssertLessThan(ReleaseVersion("v1.9.9")!, ReleaseVersion("1.10.0")!)
        XCTAssertEqual(ReleaseVersion("1.2"), ReleaseVersion("1.2.0"))
        XCTAssertEqual(ReleaseVersion("0.1.0"), ReleaseVersion("v0.1.0"))
        for invalid in ["", "v", "1..2", "1.2.3.4", "1.2.3-beta", "-1.0", "1. 2", "١.٢"] {
            XCTAssertNil(ReleaseVersion(invalid), invalid)
        }
    }
    func testOnlyProjectReleaseLinksAreOpened() throws {
        func release(_ url: String) throws -> GitHubRelease {
            let json = "{\"tag_name\":\"v1.0.0\",\"html_url\":\"\(url)\",\"draft\":false,\"prerelease\":false}"
            return try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        }
        XCTAssertNotNil(try release("https://github.com/JoonNeuro/ThisIsNotFree/releases/tag/v1.0.0").trustedURL)
        XCTAssertNil(try release("http://github.com/JoonNeuro/ThisIsNotFree/releases/tag/v1.0.0").trustedURL)
        XCTAssertNil(try release("https://github.com/other/project/releases/tag/v1.0.0").trustedURL)
        XCTAssertNil(try release("https://github.com.evil.test/JoonNeuro/ThisIsNotFree/releases/tag/v1.0.0").trustedURL)
    }
    func testCPUUsageUsesIntervalAndRejectsResetCounters() {
        let first = CPUSample(busy: 100, idle: 100)
        XCTAssertEqual(CPUSample(busy: 125, idle: 175).usage(since: first), 0.25)
        XCTAssertNil(first.usage(since: first))
        XCTAssertNil(CPUSample(busy: 1, idle: 2).usage(since: first))
    }

    func testGroupCustomizationSurvivesRelaunch() async {
        await MainActor.run {
            let name = "ThisIsNotFree.GroupTests.\(UUID())"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let store = ToolGroups(defaults: defaults)
            let id = store.add()
            store.update(id) { $0.name = "My Controls"; $0.showInMenuBar = true }
            store.toggleMember("system:wifi", group: id)
            store.toggleMember("external:example.app:item:0", group: id)
            store.moveMember("external:example.app:item:0", group: id, offset: -1)
            let reloaded = ToolGroups(defaults: defaults).groups.first { $0.id == id }
            XCTAssertEqual(reloaded?.name, "My Controls")
            XCTAssertEqual(reloaded?.members, ["external:example.app:item:0", "system:wifi"])
            XCTAssertEqual(reloaded?.showInMenuBar, true)
            store.remove(id)
            XCTAssertNil(ToolGroups(defaults: defaults).groups.first { $0.id == id })
        }
    }

    func testOnboardingChoicesSurviveRelaunch() async {
        await MainActor.run {
            let name = "ThisIsNotFree.PreferenceTests.\(UUID())"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let preferences = HubPreferences(defaults: defaults)
            XCTAssertFalse(preferences.setupComplete)
            preferences.modules = ["awake", "shelf"]
            preferences.accent = .purple
            preferences.setupComplete = true
            let restored = HubPreferences(defaults: defaults)
            XCTAssertTrue(restored.setupComplete)
            XCTAssertTrue(restored.enabled(.awake))
            XCTAssertFalse(restored.enabled(.audio))
            XCTAssertEqual(restored.accent, .purple)
        }
    }
}
