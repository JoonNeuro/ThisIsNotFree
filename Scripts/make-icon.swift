import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        context.addPath(CGPath(roundedRect: CGRect(x: 26, y: 26, width: 972, height: 972), cornerWidth: 215, cornerHeight: 215, transform: nil))
        context.clip()
        let colors = [CGColor(red: 0.18, green: 0.39, blue: 0.98, alpha: 1), CGColor(red: 0.57, green: 0.19, blue: 0.87, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 120, y: 930), end: CGPoint(x: 900, y: 80), options: [])
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.97))
        context.setLineWidth(38); context.setLineJoin(.round); context.setLineCap(.round)
        let edges: [[CGPoint]] = [
            [.init(x: 252, y: 630), .init(x: 512, y: 770), .init(x: 772, y: 630), .init(x: 512, y: 490), .init(x: 252, y: 630)],
            [.init(x: 252, y: 630), .init(x: 252, y: 350), .init(x: 512, y: 210), .init(x: 772, y: 350), .init(x: 772, y: 630)],
            [.init(x: 512, y: 490), .init(x: 512, y: 210)],
            [.init(x: 382, y: 700), .init(x: 642, y: 560), .init(x: 642, y: 455)]
        ]
        for edge in edges { context.addLines(between: edge); context.strokePath() }
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(filename) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not create icon") }
    }
}

// ICNS accepts PNG payloads for the modern icon sizes, avoiding iconutil's helper service.
var chunks = Data()
for (type, name) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"),
                     ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let png = try Data(contentsOf: output.appendingPathComponent(name))
    chunks.append(Data(type.utf8))
    var length = UInt32(png.count + 8).bigEndian
    withUnsafeBytes(of: &length) { chunks.append(contentsOf: $0) }
    chunks.append(png)
}
var icon = Data("icns".utf8)
var length = UInt32(chunks.count + 8).bigEndian
withUnsafeBytes(of: &length) { icon.append(contentsOf: $0) }
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments.dropFirst(2).first ?? "Resources/AppIcon.icns"))
