import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

enum IconTarget: String { case app, menuBar }
enum MenuIconStyle: String, CaseIterable, Identifiable {
    case zero, dollar, box, star, custom
    var id: String { rawValue }
    var title: String {
        switch self { case .zero: return "Zero Coin"; case .dollar: return "Dollar Coin"; case .box: return "Toolbox"; case .star: return "Star"; case .custom: return "Custom Image" }
    }
}

enum IconImportError: LocalizedError {
    case invalidImage, tooLarge, busy
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Choose a valid PNG, JPEG, TIFF, HEIC, or ICNS image."
        case .tooLarge: return "Choose an image smaller than 20 MB."
        case .busy: return "Wait for the current icon import to finish."
        }
    }
}

enum IconDecoder {
    // Decode a bounded thumbnail instead of loading a potentially huge bitmap.
    static func png(at url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 20_000_000 else { throw IconImportError.tooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { throw IconImportError.invalidImage }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw IconImportError.invalidImage }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw IconImportError.invalidImage }
        return data as Data
    }
}

@MainActor
final class IconAppearance: ObservableObject {
    @Published private(set) var appImage: NSImage
    @Published private(set) var menuImage: NSImage
    @Published private(set) var hasCustomApp = false
    @Published private(set) var hasCustomMenu = false
    @Published private(set) var importing = false
    @Published var error: String?
    @Published var style: MenuIconStyle {
        didSet { if !preview { defaults.set(style.rawValue, forKey: "icons.menuStyle") }; refreshMenu() }
    }
    @Published var monochrome: Bool {
        didSet { if !preview { defaults.set(monochrome, forKey: "icons.monochrome") }; refreshMenu() }
    }
    private var customMenu: NSImage?
    private let directory: URL
    private let defaults: UserDefaults
    private let preview: Bool

    init(directory: URL? = nil, defaults: UserDefaults = .standard, preview: Bool = false) {
        self.defaults = defaults
        self.preview = preview
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ThisIsNotFree/Icons")
        style = preview ? .zero : MenuIconStyle(rawValue: defaults.string(forKey: "icons.menuStyle") ?? "zero") ?? .zero
        monochrome = preview ? true : defaults.object(forKey: "icons.monochrome") as? Bool ?? true
        appImage = BrandIcon.app
        menuImage = BrandIcon.menuBar
        if !preview {
            if let image = NSImage(contentsOf: file(.app)) { appImage = image; hasCustomApp = true }
            if let image = NSImage(contentsOf: file(.menuBar)) { customMenu = image; hasCustomMenu = true }
        }
        if style == .custom && !hasCustomMenu { style = .zero }
        refreshMenu()
    }
    private func file(_ target: IconTarget) -> URL { directory.appendingPathComponent(target.rawValue + ".png") }
    private func refreshMenu() {
        let image: NSImage
        switch style {
        case .zero: image = BrandIcon.menuBar
        case .dollar: image = BrandIcon.dollar
        case .box: image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "Toolbox") ?? BrandIcon.menuBar
        case .star: image = NSImage(systemSymbolName: "star.circle.fill", accessibilityDescription: "Star") ?? BrandIcon.menuBar
        case .custom: image = customMenu ?? BrandIcon.menuBar
        }
        let resized = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            let size = image.size
            guard size.width > 0, size.height > 0 else { return false }
            let scale = min(rect.width / size.width, rect.height / size.height)
            let width = size.width * scale, height = size.height * scale
            image.draw(in: NSRect(x: (rect.width - width) / 2, y: (rect.height - height) / 2, width: width, height: height))
            return true
        }
        resized.isTemplate = style != .custom || monochrome
        resized.accessibilityDescription = "This Is Not Free"
        menuImage = resized
    }
    func choose(_ target: IconTarget) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, UTType(filenameExtension: "icns") ?? .image]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.prompt = "Use Icon"
        panel.message = target == .app ? "Choose an image for the Dock and toolbox window." : "Choose an icon for the shared menu bar button. A transparent PNG works best."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await importImage(at: url, for: target) }
            catch { self.error = error.localizedDescription }
        }
    }
    func importImage(at url: URL, for target: IconTarget) async throws {
        guard !importing else { throw IconImportError.busy }
        importing = true; error = nil
        defer { importing = false }
        let data = try await Task.detached(priority: .userInitiated) { try IconDecoder.png(at: url) }.value
        guard let image = NSImage(data: data) else { throw IconImportError.invalidImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: file(target), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(target).path)
        if target == .app { appImage = image; hasCustomApp = true }
        else { customMenu = image; hasCustomMenu = true; style = .custom }
    }
    func reset(_ target: IconTarget) {
        guard !importing else { return }
        do {
            if FileManager.default.fileExists(atPath: file(target).path) { try FileManager.default.removeItem(at: file(target)) }
            if target == .app { appImage = BrandIcon.app; hasCustomApp = false }
            else { customMenu = nil; hasCustomMenu = false; style = .zero; monochrome = true }
            error = nil
        } catch { self.error = "The custom icon could not be removed. Check folder access." }
    }
}
