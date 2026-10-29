import XCTest
@testable import MacAudioMixer

final class NotchTests: XCTestCase {
    func testCurvedContourHasThreeSeparatedWiFiDashesAndNoTopLine() {
        var settings = NotchCalibration(); settings.layout = .contour
        let geometry = NotchGeometry(width: 180, height: 32, calibration: settings)
        let paths = geometry.paths
        let wifi = paths[.wifi]!, volume = paths[.volume]!, battery = paths[.battery]!
        let dashes = geometry.wifiDashes()
        XCTAssertEqual(dashes.count, 3)
        XCTAssertTrue(dashes.allSatisfy { $0.length > 0 })
        XCTAssertEqual(dashes[0].length, dashes[2].length, accuracy: 0.01)
        XCTAssertTrue(zip(dashes, dashes.dropFirst()).allSatisfy { a, b in
            hypot(a.points.last!.x - b.points.first!.x, a.points.last!.y - b.points.first!.y) > geometry.calibration.thickness
        })
        XCTAssertTrue(wifi.points.contains { $0.x < geometry.padding && $0.y > 0 })
        XCTAssertGreaterThan(Set(wifi.points.map(\.x)).count, 20, "The edge must follow curves, not three straight bars")
        XCTAssertEqual(wifi.points.first!.y, 0, accuracy: 0.000001)
        XCTAssertEqual(volume.points.last!.y, 0, accuracy: 0.000001)
        XCTAssertEqual(battery.points.first!.y, battery.points.last!.y)
        XCTAssertLessThan(wifi.points.last!.x, battery.points.first!.x)
        XCTAssertLessThan(battery.points.last!.x, volume.points.first!.x)
        XCTAssertNil(geometry.zone(at: .init(x: geometry.size.width/2, y: 3)), "The camera interior must never consume clicks")
        XCTAssertNil(geometry.zone(at: .init(x: geometry.size.width/2, y: geometry.height + 12)), "The desktop below must remain click-through")
        XCTAssertEqual(geometry.zone(at: battery.points.first!), .battery)
    }

    func testBatteryReaderUsesOnlyReportedConnectedValues() throws {
        let json = #"{"SPBluetoothDataType":[{"device_connected":[{"Earbuds":{"device_address":"AA","device_batteryLevelLeft":"62%","device_batteryLevelCase":"41%"}},{"Mouse":{"device_address":"BB","device_batteryLevelMain":78}},{"Unknown":{"device_batteryLevelCase":"not available"}}],"device_not_connected":[{"Old":{"device_batteryLevelMain":"100%"}}]}]}"#
        let values = PeripheralBatteryReader.parse(Data(json.utf8))
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values.first { $0.id == "AA:Left" }?.level, 0.62)
        XCTAssertEqual(values.first { $0.id == "AA:Case" }?.level, 0.41)
        XCTAssertFalse(values.contains { $0.name.contains("Old") || $0.name.contains("Unknown") })
        XCTAssertEqual(PeripheralBatteryReader.parse(Data("{}".utf8)), [])
    }

    func testContourScalesAndHitRegionsStayOnTheEdge() {
        for height in [20.0, 32, 38] {
            for width in [140.0, 180, 220] {
                var calibration = NotchCalibration(); calibration.layout = .contour; calibration.separation = 7; calibration.thickness = 4
                let geometry = NotchGeometry(width: width, height: height, calibration: calibration)
                for (zone, path) in geometry.paths {
                    XCTAssertGreaterThan(path.length, 0)
                    XCTAssertTrue(path.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                    XCTAssertEqual(geometry.zone(at: path.points[path.points.count/2]), zone)
                }
                XCTAssertNil(geometry.zone(at: .init(x: geometry.size.width / 2, y: height / 2)))
            }
        }
    }
    func testDefaultSideLayoutHasExactlyThreeDotsAndNoBottomHitRegion() {
        let geometry = NotchGeometry(width: 185, height: 32, calibration: .init())
        XCTAssertEqual(Set(geometry.paths.keys), [.wifi, .battery])
        let dots = geometry.wifiDashes()
        XCTAssertEqual(dots.count, 3)
        XCTAssertTrue(dots.allSatisfy { $0.length > 0 && $0.length < 0.1 })
        let battery = geometry.paths[.battery]!
        XCTAssertEqual(battery.points.first!.x, battery.points.last!.x)
        XCTAssertGreaterThan(battery.points.first!.y, battery.points.last!.y)
        XCTAssertNil(geometry.zone(at: .init(x: geometry.size.width/2, y: geometry.height)))
        XCTAssertNil(geometry.zone(at: .init(x: geometry.size.width/2, y: 5)))
    }

    func testOldPreferencesDecodeIntoSideLayoutWithoutLosingMenuMapping() throws {
        let data = Data(#"{"shoulder":5,"corner":9,"thickness":2,"separation":3,"widthAdjustment":0,"heightAdjustment":0,"menuItems":{"wifi":"saved-item"}}"#.utf8)
        let decoded = try JSONDecoder().decode(NotchCalibration.self, from: data)
        XCTAssertTrue(decoded.sideOnly)
        XCTAssertEqual(decoded.menuItems["wifi"], "saved-item")
    }

}
