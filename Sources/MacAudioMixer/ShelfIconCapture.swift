import AppKit
import ScreenCaptureKit

@MainActor
enum ShelfIconCapture {
    static func capture(_ items: [ShelfItem]) async throws -> [String: NSImage] {
        // Capture only each visible status item's rectangle, never a desktop or
        // application window. Snapshots remain in memory and are never uploaded.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var images: [String: NSImage] = [:]
        for item in items {
            guard let rect = item.frame, rect.width > 0, rect.width <= 600, rect.height > 0, rect.height <= 64,
                  let display = content.displays.first(where: {
                      let bounds = CGDisplayBounds($0.displayID)
                      return bounds.contains(rect) && rect.minY >= bounds.minY && rect.maxY <= bounds.minY + 64
                  }) else { continue }
            let bounds = CGDisplayBounds(display.displayID)
            let scale = CGFloat(display.width) / bounds.width
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: rect.minX-bounds.minX, y: rect.minY-bounds.minY, width: rect.width, height: rect.height)
            configuration.width = max(1, Int((rect.width * scale).rounded(.up)))
            configuration.height = max(1, Int((rect.height * scale).rounded(.up)))
            configuration.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            images[item.id] = NSImage(cgImage: image, size: rect.size)
        }
        return images
    }
}
