import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let artworkURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst(3).first ?? "Resources/Brand/ZeroBanknote-v1.png")
guard let source = CGImageSourceCreateWithURL(artworkURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Could not load icon artwork") }
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        context.addPath(CGPath(roundedRect: CGRect(x: 26, y: 26, width: 972, height: 972), cornerWidth: 215, cornerHeight: 215, transform: nil))
        context.clip()
        context.interpolationQuality = .high
        context.draw(artwork, in: CGRect(x: 26, y: 26, width: 972, height: 972))
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
