import AppKit

// AppKit supplies the housing's bounding region, not its physical corner radii.
// Keep the contour calibrated independently from the measured screen geometry.
enum NotchZone: String, CaseIterable, Identifiable {
    case wifi, battery, volume
    var id: String { rawValue }
    var title: String { switch self { case .wifi: return "Wi-Fi"; case .battery: return "Battery"; case .volume: return "Sound" } }
    var menuKeys: [String] { switch self { case .wifi: return ["wifi"]; case .battery: return ["battery"]; case .volume: return ["sound", "volume"] } }
}

struct NotchCalibration: Codable, Equatable {
    var shoulder: Double = 5
    var corner: Double = 9
    var thickness: Double = 2
    var separation: Double = 3
    var widthAdjustment: Double = 0
    var heightAdjustment: Double = 0
    var menuItems: [String: String] = [:]
}

struct NotchPolyline {
    let points: [CGPoint]
    var length: CGFloat { zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) } }
    func slice(_ from: CGFloat, _ to: CGFloat) -> NotchPolyline {
        let total = length
        let a = min(max(from, 0), total), b = min(max(to, 0), total)
        guard b > a else { return .init(points: []) }
        var walked: CGFloat = 0, result: [CGPoint] = []
        for (p, q) in zip(points, points.dropFirst()) {
            let distance = hypot(q.x - p.x, q.y - p.y)
            defer { walked += distance }
            guard distance > 0, walked + distance >= a, walked <= b else { continue }
            for t in [max(0, (a - walked) / distance), min(1, (b - walked) / distance)] {
                let point = CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
                if result.last != point { result.append(point) }
            }
        }
        return .init(points: result)
    }
    func distance(to point: CGPoint) -> CGFloat {
        zip(points, points.dropFirst()).map { p, q in
            let dx = q.x - p.x, dy = q.y - p.y
            let square = dx * dx + dy * dy
            let t = square > 0 ? min(1, max(0, ((point.x - p.x) * dx + (point.y - p.y) * dy) / square)) : 0
            return hypot(point.x - p.x - t * dx, point.y - p.y - t * dy)
        }.min() ?? .infinity
    }
    func stroke(_ color: NSColor, width: CGFloat) {
        guard let first = points.first, points.count > 1 else { return }
        let path = NSBezierPath(); path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        color.setStroke(); path.stroke()
    }
}

struct NotchGeometry {
    let width: CGFloat
    let height: CGFloat
    let calibration: NotchCalibration
    var padding: CGFloat { max(16, calibration.shoulder + calibration.thickness + 4) }
    var size: CGSize { .init(width: width + 2 * padding, height: height + 12) }
    // Flipped coordinates: top display edge is y=0. Offset the centerline so the
    // stroke lies outside the camera housing, rather than being clipped by it.
    var paths: [NotchZone: NotchPolyline] {
        let offset = CGFloat(calibration.thickness) / 2 + 0.5
        let l = padding - offset, r = padding + width + offset, bottom = height + offset
        let upper = min(CGFloat(calibration.shoulder), height * 0.45)
        let lower = min(CGFloat(calibration.corner) + offset, height * 0.55)
        func curve(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint) -> [CGPoint] {
            (0...24).map { i in
                let t = CGFloat(i) / 24, u = 1 - t
                return CGPoint(x: u*u*a.x + 2*u*t*c.x + t*t*b.x, y: u*u*a.y + 2*u*t*c.y + t*t*b.y)
            }
        }
        let left = curve(.init(x: l-upper, y: 0), .init(x: l, y: 0), .init(x: l, y: upper)) +
            curve(.init(x: l, y: bottom-lower), .init(x: l, y: bottom), .init(x: l+lower, y: bottom))
        let right = curve(.init(x: r-lower, y: bottom), .init(x: r, y: bottom), .init(x: r, y: bottom-lower)) +
            curve(.init(x: r, y: upper), .init(x: r, y: 0), .init(x: r+upper, y: 0))
        let halfGap = CGFloat(calibration.separation + calibration.thickness) / 2
        let lp = NotchPolyline(points: left), rp = NotchPolyline(points: right)
        return [.wifi: lp.slice(0, lp.length-halfGap),
                .battery: .init(points: [.init(x: l+lower+halfGap, y: bottom), .init(x: r-lower-halfGap, y: bottom)]),
                .volume: rp.slice(halfGap, rp.length)]
    }
    func zone(at point: CGPoint, tolerance: CGFloat = 6) -> NotchZone? {
        let closest = paths.map { ($0.key, $0.value.distance(to: point)) }.min { $0.1 < $1.1 }
        return closest.flatMap { $0.1 <= tolerance ? $0.0 : nil }
    }
    func wifiDashes() -> [NotchPolyline] {
        let path = paths[.wifi]!
        let gap = CGFloat(calibration.separation + calibration.thickness)
        let dash = max(0, (path.length - gap * 2) / 3)
        return (0..<3).map { i in path.slice(CGFloat(i) * (dash + gap), CGFloat(i) * (dash + gap) + dash) }
    }
}
