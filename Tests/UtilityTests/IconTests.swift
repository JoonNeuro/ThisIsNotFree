import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import MacAudioMixer

final class IconTests: XCTestCase {
    private func makePNG(_ url: URL, width: Int = 32, height: Int = 24) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 4, y: 4, width: width - 8, height: height - 8))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    @MainActor
    func testIconImportRelaunchModesAndIndependentReset() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = "ThisIsNotFree.IconTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { try? FileManager.default.removeItem(at: base); defaults.removePersistentDomain(forName: name) }
        let input = base.appendingPathComponent("input.png")
        try makePNG(input, width: 2048, height: 1024)
        let directory = base.appendingPathComponent("stored")
        let icons = IconAppearance(directory: directory, defaults: defaults)
        XCTAssertEqual(icons.style, .zero)
        XCTAssertTrue(icons.menuImage.isTemplate)
        try await icons.importImage(at: input, for: .app)
        try await icons.importImage(at: input, for: .menuBar)
        XCTAssertTrue(icons.hasCustomApp)
        XCTAssertTrue(icons.hasCustomMenu)
        XCTAssertEqual(icons.style, .custom)
        XCTAssertLessThanOrEqual(icons.appImage.size.width, 1024)
        icons.monochrome = false
        XCTAssertFalse(icons.menuImage.isTemplate)
        XCTAssertEqual(icons.menuImage.size, NSSize(width: 20, height: 20))
        try FileManager.default.removeItem(at: input)
        let restored = IconAppearance(directory: directory, defaults: defaults)
        XCTAssertTrue(restored.hasCustomApp, "Copies must survive removal of the source image")
        XCTAssertTrue(restored.hasCustomMenu)
        XCTAssertEqual(restored.style, .custom)
        XCTAssertFalse(restored.monochrome)
        restored.reset(.app)
        XCTAssertFalse(restored.hasCustomApp)
        XCTAssertTrue(restored.hasCustomMenu, "App and menu icons reset independently")
        restored.reset(.menuBar)
        XCTAssertFalse(restored.hasCustomMenu)
        XCTAssertEqual(restored.style, .zero)
        XCTAssertTrue(restored.menuImage.isTemplate)
        let reset = IconAppearance(directory: directory, defaults: defaults)
        XCTAssertFalse(reset.hasCustomApp)
        XCTAssertFalse(reset.hasCustomMenu)
        XCTAssertEqual(reset.style, .zero)
    }

    @MainActor
    func testRejectedImportKeepsPreviousIconAndMissingCustomFallsBack() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = "ThisIsNotFree.IconTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { try? FileManager.default.removeItem(at: base); defaults.removePersistentDomain(forName: name) }
        defaults.set("custom", forKey: "icons.menuStyle")
        let icons = IconAppearance(directory: base.appendingPathComponent("stored"), defaults: defaults)
        XCTAssertEqual(icons.style, .zero)
        let input = base.appendingPathComponent("image.png")
        try makePNG(input)
        try await icons.importImage(at: input, for: .menuBar)
        let stored = try Data(contentsOf: base.appendingPathComponent("stored/menuBar.png"))
        try Data("not an image".utf8).write(to: input)
        do { try await icons.importImage(at: input, for: .menuBar); XCTFail("Invalid input accepted") } catch { }
        XCTAssertEqual(icons.style, .custom)
        XCTAssertEqual(try Data(contentsOf: base.appendingPathComponent("stored/menuBar.png")), stored)
        XCTAssertFalse(icons.importing)
        let handle = try FileHandle(forWritingTo: input)
        try handle.truncate(atOffset: 21_000_000)
        try handle.close()
        do { _ = try IconDecoder.png(at: input); XCTFail("Oversize input accepted") }
        catch { XCTAssertTrue(error is IconImportError) }
    }
}
