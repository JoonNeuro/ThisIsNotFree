import AppKit

@MainActor
enum BrandIcon {
    // A wide mouth only: a transparent tooth opening and a single tooth division
    // keep the F articulation readable without painting textures at menu bar size.
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 24, height: 16), flipped: false) { _ in
            let lips = NSBezierPath()
            lips.windingRule = .evenOdd
            lips.move(to: NSPoint(x: 1, y: 7))
            lips.curve(to: NSPoint(x: 7, y: 14), controlPoint1: NSPoint(x: 3.8, y: 9.8), controlPoint2: NSPoint(x: 5.5, y: 14.6))
            lips.curve(to: NSPoint(x: 12, y: 12.7), controlPoint1: NSPoint(x: 9, y: 14.4), controlPoint2: NSPoint(x: 10.3, y: 12.6))
            lips.curve(to: NSPoint(x: 17, y: 14), controlPoint1: NSPoint(x: 13.6, y: 12.6), controlPoint2: NSPoint(x: 15, y: 14.4))
            lips.curve(to: NSPoint(x: 23, y: 7), controlPoint1: NSPoint(x: 18.5, y: 14.6), controlPoint2: NSPoint(x: 20.3, y: 9.8))
            lips.curve(to: NSPoint(x: 12, y: 1), controlPoint1: NSPoint(x: 20, y: 2), controlPoint2: NSPoint(x: 16, y: 1))
            lips.curve(to: NSPoint(x: 1, y: 7), controlPoint1: NSPoint(x: 8, y: 1), controlPoint2: NSPoint(x: 4, y: 2))
            lips.close()
            lips.move(to: NSPoint(x: 3.4, y: 7))
            lips.curve(to: NSPoint(x: 12, y: 10), controlPoint1: NSPoint(x: 6.2, y: 8.3), controlPoint2: NSPoint(x: 9.2, y: 10))
            lips.curve(to: NSPoint(x: 20.6, y: 7), controlPoint1: NSPoint(x: 14.8, y: 10), controlPoint2: NSPoint(x: 17.8, y: 8.3))
            lips.curve(to: NSPoint(x: 12, y: 6.6), controlPoint1: NSPoint(x: 17, y: 6.5), controlPoint2: NSPoint(x: 14, y: 6.6))
            lips.curve(to: NSPoint(x: 3.4, y: 7), controlPoint1: NSPoint(x: 10, y: 6.6), controlPoint2: NSPoint(x: 7, y: 6.5))
            lips.close()
            NSColor.black.setFill()
            lips.fill()
            NSBezierPath(rect: NSRect(x: 11.65, y: 7, width: 0.7, height: 3)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "This Is Not Free"
        return image
    }()
}
