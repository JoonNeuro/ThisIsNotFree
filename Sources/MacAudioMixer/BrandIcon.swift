import AppKit

@MainActor
enum BrandIcon {
    static let menuBar = coin("0")
    static let dollar = coin("$")

    private static func coin(_ marking: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 18, height: 18)).fill()
            let dollar = NSAttributedString(string: marking, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor.black])
            let size = dollar.size()
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.setBlendMode(.destinationOut)
            dollar.draw(at: NSPoint(x: (20 - size.width) / 2, y: (20 - size.height) / 2))
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "This Is Not Free"
        return image
    }
    static let app: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "banknote", accessibilityDescription: "This Is Not Free") ?? NSImage(size: NSSize(width: 128, height: 128))
    }()
}
