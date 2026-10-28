import XCTest
@testable import MacAudioMixer

final class StorageTests: XCTestCase {
    private func file(_ bytes: Int64, _ modified: Int64 = 1) -> StorageFile { .init(bytes: bytes, modified: modified) }


    @MainActor
    func testHistorySurvivesRelaunchAndRemovedWatchStaysRemoved() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("watched")
        let history = base.appendingPathComponent("state/history.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let tracker = StorageTracker(archiveURL: history)
        defer { tracker.stop() }
        tracker.start()
        for _ in 0..<200 where tracker.loading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(tracker.loading)
        tracker.addRoot(root.path)
        for _ in 0..<200 where tracker.scanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(tracker.events.count, 1)
        XCTAssertNil(tracker.events.last?.delta)
        await tracker.waitForPendingWrites()
        tracker.stop()

        try Data(repeating: 29, count: 65536).write(to: root.appendingPathComponent("new.bin"))
        let restored = StorageTracker(archiveURL: history)
        defer { restored.stop() }
        restored.start()
        for _ in 0..<200 where restored.loading || restored.scanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(restored.roots.count, 1)
        XCTAssertEqual(restored.events.last?.added, 1)
        XCTAssertGreaterThan(restored.events.last?.delta ?? 0, 0)
        await restored.waitForPendingWrites()
        restored.removeRoot(try XCTUnwrap(restored.roots.first))
        await restored.waitForPendingWrites()
        restored.stop()

        let empty = StorageTracker(archiveURL: history)
        defer { empty.stop() }
        empty.start()
        for _ in 0..<200 where empty.loading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(empty.roots.isEmpty)
        XCTAssertTrue(empty.events.isEmpty)
        await empty.waitForPendingWrites()
    }

    func testChangesIncludeRemovedFilesAndGroupGrowth() {
        let before = StorageScan(path: "/fixture", date: Date(timeIntervalSince1970: 1),
                                 files: ["output/a.bin": file(100), "old.bin": file(400), "same": file(10)], issues: [])
        let after = StorageScan(path: "/fixture", date: Date(timeIntervalSince1970: 2),
                                files: ["output/a.bin": file(300), "output/new.bin": file(500), "same": file(10)], issues: [])
        let event = StorageEvent.comparing(after, to: before)
        XCTAssertEqual(event.delta, 300)
        XCTAssertEqual(event.added, 1)
        XCTAssertEqual(event.removed, 1)
        XCTAssertEqual(event.modified, 1)
        XCTAssertEqual(event.folders.first?.path, "output")
        XCTAssertEqual(event.folders.first?.delta, 700)
        XCTAssertTrue(event.changes.contains { $0.path == "old.bin" && $0.delta == -400 })
        XCTAssertEqual(event.since, before.date)
    }

    func testIncompleteScanAndDifferentRootDoNotReportFalseDeletions() {
        let baseline = StorageScan(path: "/fixture", date: Date(), files: ["private.bin": file(900)], issues: [])
        let partial = StorageScan(path: "/fixture", date: Date(), files: [:], issues: ["Access denied"])
        let event = StorageEvent.comparing(partial, to: baseline)
        XCTAssertNil(event.delta)
        XCTAssertEqual(event.removed, 0)
        XCTAssertTrue(event.changes.isEmpty)
        XCTAssertNil(StorageEvent.comparing(baseline, to: partial).delta)
        let unrelated = StorageScan(path: "/other", date: Date(), files: [:], issues: [])
        XCTAssertNil(StorageEvent.comparing(unrelated, to: baseline).delta)
    }

    func testScannerUsesAllocatedBytesAndDoesNotFollowLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try Data(repeating: 37, count: 1_048_576).write(to: root.appendingPathComponent("local.bin"))
        try Data(repeating: 11, count: 4096).write(to: outside.appendingPathComponent("excluded.bin"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested/deep"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("nested/deep/local.bin"))
        let sparse = root.appendingPathComponent("sparse.img")
        XCTAssertTrue(FileManager.default.createFile(atPath: sparse.path, contents: nil))
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 1_000_000_000)
        try handle.close()
        let scan = StorageScanner.scan(root.path)
        XCTAssertTrue(scan.complete, scan.issues.joined(separator: ", "))
        XCTAssertEqual(Set(scan.files.keys), ["local.bin", "sparse.img", "nested/deep/local.bin"])
        XCTAssertLessThan(try XCTUnwrap(scan.files["sparse.img"]).bytes, 10_000_000)
        XCTAssertGreaterThan(try XCTUnwrap(scan.files["local.bin"]).bytes, 0)
        XCTAssertFalse(StorageScanner.scan(root.path, limit: 1).complete)
        XCTAssertFalse(StorageScanner.scan(root.path, cancelled: { true }).complete)
        XCTAssertFalse(StorageScanner.scan(outside.appendingPathComponent("missing").path).complete)
        let roundTrip = try JSONDecoder().decode(StorageScan.self, from: JSONEncoder().encode(scan))
        XCTAssertEqual(roundTrip.files, scan.files)
    }
}
