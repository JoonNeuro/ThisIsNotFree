import XCTest
@testable import MacAudioMixer

final class LivePreviewTests: XCTestCase {
    @MainActor
    func testAudioPreviewReadersShareReadOnlyModelAndReleaseIt() {
        let name = "ThisIsNotFree.LivePreviewTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = HubPreferences(defaults: defaults)
        let hub = UtilityHub(preferences: preferences)
        defer { hub.shutdown() }
        XCTAssertNil(hub.mixer)
        XCTAssertNil(hub.previewMixer)
        let first = UUID(), second = UUID()
        hub.acquirePreview(.audio, reader: first)
        let model = hub.previewMixer
        XCTAssertNotNil(model)
        XCTAssertTrue(model?.readOnly == true)
        model?.requestPermission()
        XCTAssertFalse(model?.requestingPermission ?? true)
        hub.acquirePreview(.audio, reader: second)
        XCTAssertTrue(model === hub.previewMixer)
        hub.releasePreview(.audio, reader: first)
        XCTAssertTrue(model === hub.previewMixer)
        hub.releasePreview(.audio, reader: second)
        XCTAssertNil(hub.previewMixer)
        XCTAssertNil(hub.mixer)
        XCTAssertTrue(preferences.modules.isEmpty)
        XCTAssertFalse(preferences.setupComplete)
    }

    @MainActor
    func testDiskPreviewReadsSavedHistoryWithoutRescanningOrRewritingIt() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("watched")
        let history = base.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let recording = StorageTracker(archiveURL: history)
        recording.start()
        for _ in 0..<200 where recording.loading { try await Task.sleep(for: .milliseconds(10)) }
        recording.addRoot(root.path)
        for _ in 0..<200 where recording.scanning { try await Task.sleep(for: .milliseconds(10)) }
        recording.stop()
        await recording.waitForPendingWrites()
        let original = try Data(contentsOf: history)
        let browsing = StorageTracker(archiveURL: history)
        await browsing.refreshPreviewCapacity()
        XCTAssertEqual(browsing.roots, recording.roots)
        XCTAssertEqual(browsing.events.count, recording.events.count)
        XCTAssertFalse(browsing.scanning)
        XCTAssertNotNil(browsing.previewCapacity)
        XCTAssertEqual(try Data(contentsOf: history), original)
    }

    @MainActor
    func testDiskPreviewReadsRealVolumeWithoutCreatingHistoryOrWatchingFolders() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let tracker = StorageTracker(archiveURL: base.appendingPathComponent("history.json"))
        XCTAssertNil(tracker.latestCapacity)
        XCTAssertTrue(tracker.capacity.isEmpty)
        await tracker.refreshPreviewCapacity()
        let sample = try XCTUnwrap(tracker.latestCapacity)
        XCTAssertGreaterThan(sample.total, 0)
        XCTAssertGreaterThanOrEqual(sample.free, 0)
        XCTAssertLessThanOrEqual(sample.free, sample.total)
        XCTAssertLessThan(abs(sample.date.timeIntervalSinceNow), 10)
        XCTAssertTrue(tracker.capacity.isEmpty, "A transient reading is not history")
        XCTAssertTrue(tracker.roots.isEmpty)
        XCTAssertTrue(tracker.events.isEmpty)
        XCTAssertFalse(tracker.scanning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path), "A preview must not persist history")
    }
}
