import AppKit
import SwiftUI

@MainActor
final class NotchEdgeView: NSView {
    var geometry: NotchGeometry?
    var status = NotchStatus()
    var drawHousing = false
    var onActivate: ((NotchZone) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let geometry else { return }
        let width = CGFloat(geometry.calibration.thickness)
        let paths = geometry.paths
        if drawHousing {
            var reference = geometry.calibration; reference.layout = .contour
            let contour = NotchGeometry(width: geometry.width, height: geometry.height, calibration: reference).paths
            let points = contour[.wifi]!.points + contour[.battery]!.points + contour[.volume]!.points
            let shape = NSBezierPath(); shape.move(to: points[0]); points.dropFirst().forEach { shape.line(to: $0) }; shape.close()
            NSColor.black.setFill(); shape.fill()
        }
        let dashes = geometry.wifiDashes()
        for (i, dash) in dashes.enumerated() {
            let lit = status.wifiBars.map { i >= 3 - $0 } ?? false
            dash.stroke(NSColor.systemMint.withAlphaComponent(lit ? 1 : 0.20), width: width)
        }
        let colors: [NSColor] = [.systemMint, .systemCyan, .systemPurple, .systemOrange, .systemPink]
        let bottom = paths[.battery]!
        if status.batteries.isEmpty { bottom.stroke(.white.withAlphaComponent(0.18), width: width) }
        else {
            let count = status.batteries.count
            let gap = geometry.calibration.sideOnly ? min(CGFloat(geometry.calibration.separation), bottom.length / CGFloat(count * 3)) : CGFloat(geometry.calibration.separation) + width
            let cap: NSBezierPath.LineCapStyle = geometry.calibration.sideOnly && count > 1 ? .butt : .round
            let usable = max(0, bottom.length - gap * CGFloat(count - 1))
            // A stable, larger first section belongs to the MacBook when present.
            let hasMac = status.batteries.first?.id == "mac"
            let units = CGFloat(count + (hasMac && count > 1 ? 1 : 0))
            var offset: CGFloat = 0
            for (i, battery) in status.batteries.enumerated() {
                let length = usable / units * (hasMac && count > 1 && i == 0 ? 2 : 1)
                let rail = bottom.slice(offset, offset + length)
                let color = colors[i % colors.count]
                rail.stroke(color.withAlphaComponent(0.22), width: width, cap: cap)
                rail.slice(0, rail.length * battery.level).stroke(color, width: width, cap: cap)
                offset += length + gap
            }
        }
        if let volume = paths[.volume] {
            volume.stroke(NSColor.white.withAlphaComponent(0.2), width: width)
            if let value = status.volume { volume.slice(0, volume.length * value).stroke(NSColor(calibratedRed: 1, green: 0.92, blue: 0.72, alpha: 1), width: width) }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let zone = geometry?.zone(at: convert(event.locationInWindow, from: nil)) else { return }
        onActivate?(zone)
    }
    override func accessibilityChildren() -> [Any]? {
        guard let geometry, let window else { return [] }
        return NotchZone.allCases.compactMap { zone -> NSAccessibilityElement? in
            guard let points = geometry.paths[zone]?.points, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
            let rect = NSRect(x: minX-4, y: minY-4, width: maxX-minX+8, height: maxY-minY+8)
            let child = NotchAccessibilityButton()
            child.action = { [weak self] in self?.onActivate?(zone) }
            child.setAccessibilityRole(.button); child.setAccessibilityLabel("Open original \(zone.title) menu")
            child.setAccessibilityParent(self)
            child.setAccessibilityFrame(window.convertToScreen(convert(rect, to: nil)))
            return child
        }
    }
}

private final class NotchAccessibilityButton: NSAccessibilityElement {
    var action: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { action?(); return action != nil }
}

struct NotchEdgePreview: NSViewRepresentable {
    let geometry: NotchGeometry
    let status: NotchStatus
    func makeNSView(context: Context) -> NotchEdgeView { let view = NotchEdgeView(); view.drawHousing = true; return view }
    func updateNSView(_ view: NotchEdgeView, context: Context) { view.geometry = geometry; view.status = status; view.needsDisplay = true }
}

struct NotchHubSettingsView: View {
    @ObservedObject var model: NotchHubController
    @ObservedObject var shelf: MenuShelf
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Notch Hub").font(.headline)
                Picker("Layout", selection: Binding(get: { model.calibration.layout ?? .sides }, set: { model.calibration.layout = $0 })) {
                    ForEach(NotchLayout.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if let geometry = model.geometry {
                    VStack(spacing: 10) {
                        NotchEdgePreview(geometry: geometry, status: model.status)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        Text("\(model.screenName ?? "Display") · \(Int(geometry.width)) × \(Int(geometry.height)) pt")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.bottom, 8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    Text(model.enabled ? "The edge is active on your notched display." : "Live contour preview. Add this tool to display the edge.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("No notched display connected", systemImage: "macbook.gen2", description: Text("Open your MacBook display. The edge appears automatically on screens with a camera housing."))
                        .frame(height: 155)
                }
                HStack { Circle().fill(.mint).frame(width: 7, height: 7); Text(model.status.wifiText).font(.caption) }
                if !model.calibration.sideOnly {
                    HStack { Circle().fill(.yellow).frame(width: 7, height: 7); Text(model.status.volume.map { "Output volume \(Int(($0 * 100).rounded()))%" } ?? "Output volume unavailable for this device").font(.caption) }
                }
                ForEach(Array(model.status.batteries.enumerated()), id: \.element.id) { index, battery in
                    HStack { Circle().fill(index == 0 ? Color.mint : Color.cyan).frame(width: 7, height: 7); Text(battery.name).font(.caption); Spacer(); Text("\(Int((battery.level * 100).rounded()))%").font(.caption.monospacedDigit()) }
                }
                if model.status.batteries.isEmpty { Text("No reported battery levels. Connected accessories appear only when macOS supplies their battery data.").font(.caption).foregroundStyle(.secondary) }
                Divider()
                Text("Original system menus").font(.headline)
                Text("Click each edge to press its original menu bar item. Popup placement is controlled by macOS. Keep the original items available; some hidden items are not exposed.").font(.caption).foregroundStyle(.secondary)
                if !shelf.accessibilityGranted { Button("Allow Accessibility") { shelf.requestAccessibility() }.buttonStyle(.borderedProminent) }
                HStack {
                    ForEach(activeZones) { zone in Button(zone.title) { model.open(zone) } }
                    Button { shelf.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh menu items")
                }
                if let message = shelf.message { Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                DisclosureGroup("Choose original menu items") {
                    ForEach(activeZones) { zone in
                        Picker(zone.title, selection: Binding(get: { model.calibration.menuItems[zone.rawValue] ?? "" }, set: { model.calibration.menuItems[zone.rawValue] = $0.isEmpty ? nil : $0 })) {
                            Text("Detect automatically").tag("")
                            ForEach(shelf.items) { item in Text("\(item.appName) · \(item.title)").tag(item.id) }
                        }
                    }
                }.font(.caption)
                Divider()
                Text("Contour calibration").font(.headline)
                Text(model.calibration.sideOnly ? "Three Wi-Fi dots on the left, a vertical battery rail on the right. No bottom line. Placement follows the display's measured camera region." : "Position and size follow the display's safe-area geometry. Corner curves are an approximation. Wi-Fi uses three curved dashes.").font(.caption).foregroundStyle(.secondary)
                adjustment("Line thickness", \.thickness, 1...4)
                adjustment("Section gap", \.separation, 2...7)
                if !model.calibration.sideOnly {
                    adjustment("Upper shoulder", \.shoulder, 0...12)
                    adjustment("Lower curve", \.corner, 2...16)
                }
                adjustment("Width adjustment", \.widthAdjustment, -16...16)
                adjustment("Height adjustment", \.heightAdjustment, -8...8)
                Button("Reset Contour") { model.resetCalibration() }
                Text("Only the thin edge receives clicks. The camera area and surrounding menu bar remain click-through. Battery reads refresh every 2 seconds; accessory levels refresh every minute when available.").font(.caption2).foregroundStyle(.secondary)
            }.padding(18)
        }
    }
    private var activeZones: [NotchZone] { model.calibration.sideOnly ? [.wifi, .battery] : NotchZone.allCases }
    private func adjustment(_ title: String, _ key: WritableKeyPath<NotchCalibration, Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 115, alignment: .leading)
            Slider(value: Binding(get: { model.calibration[keyPath: key] }, set: { model.calibration[keyPath: key] = $0 }), in: range, step: 0.5)
            Text(String(format: "%.1f", model.calibration[keyPath: key])).monospacedDigit().frame(width: 32)
        }.font(.caption)
    }
}
