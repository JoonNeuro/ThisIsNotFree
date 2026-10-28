import AppKit

@MainActor
enum BrandIcon {
    // Exaggerated F: broad upper incisors press deep into the lower lip.
    // Transparent openings and a single tooth division survive menu bar size.
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
            lips.move(to: NSPoint(x: 3.2, y: 7))
            lips.curve(to: NSPoint(x: 8.2, y: 10.6), controlPoint1: NSPoint(x: 5, y: 7.4), controlPoint2: NSPoint(x: 6.7, y: 10.4))
            lips.curve(to: NSPoint(x: 12, y: 10.3), controlPoint1: NSPoint(x: 9.5, y: 11), controlPoint2: NSPoint(x: 11, y: 10.5))
            lips.curve(to: NSPoint(x: 16, y: 10.5), controlPoint1: NSPoint(x: 13.2, y: 10.7), controlPoint2: NSPoint(x: 14.5, y: 11))
            lips.curve(to: NSPoint(x: 20.8, y: 7), controlPoint1: NSPoint(x: 17.5, y: 10.2), controlPoint2: NSPoint(x: 19, y: 7.3))
            lips.curve(to: NSPoint(x: 15.5, y: 7.2), controlPoint1: NSPoint(x: 19, y: 6.8), controlPoint2: NSPoint(x: 17.3, y: 7.4))
            lips.curve(to: NSPoint(x: 12.1, y: 4.9), controlPoint1: NSPoint(x: 15.3, y: 5.9), controlPoint2: NSPoint(x: 13.4, y: 4.9))
            lips.curve(to: NSPoint(x: 8.5, y: 7.2), controlPoint1: NSPoint(x: 10.5, y: 5.1), controlPoint2: NSPoint(x: 8.8, y: 5.9))
            lips.curve(to: NSPoint(x: 3.2, y: 7), controlPoint1: NSPoint(x: 6.7, y: 7.5), controlPoint2: NSPoint(x: 5, y: 6.8))
            lips.close()
            NSColor.black.setFill()
            lips.fill()
            NSBezierPath(rect: NSRect(x: 11.65, y: 5, width: 0.7, height: 5.4)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "This Is Not Free"
        return image
    }()
}
