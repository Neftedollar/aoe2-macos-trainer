import Foundation
import XCTest
@testable import AoE2MacTrainer

final class HUDTests: XCTestCase {
    func testOCRClockParsing() {
        XCTAssertEqual(HUDTextParser.value("12:34", for: .clock), 754)
        XCTAssertEqual(HUDTextParser.value("01:02:03", for: .clock), 3723)
        XCTAssertNil(HUDTextParser.value("13:90", for: .clock))
        XCTAssertNil(HUDTextParser.value("not time", for: .clock))
    }

    func testResourceAndVillagerParsing() {
        XCTAssertEqual(HUDTextParser.value("1,234", for: .wood), 1234)
        XCTAssertEqual(HUDTextParser.value("23/30", for: .villagers), 23)
        XCTAssertNil(HUDTextParser.value("food 40", for: .food))
        XCTAssertNil(HUDTextParser.value("1000", for: .villagers))
    }

    func testStockpileRatesIncludeSpending() {
        let start = Date(timeIntervalSince1970: 1000)
        var trends = ResourceTrends()
        trends.add(HUDSnapshot(capturedAt: start, values: [.wood: 200]))
        XCTAssertNil(trends.netPerGameMinute(for: .wood))
        trends.add(HUDSnapshot(capturedAt: start.addingTimeInterval(30), values: [.wood: 170]))
        XCTAssertEqual(trends.netPerGameMinute(for: .wood), -35)
    }

    func testInvalidRegionsAreRejected() {
        XCTAssertFalse(NormalizedHUDRect(x: 0.9, y: 0, width: 0.5, height: 0.1).isValid)
        XCTAssertTrue(NormalizedHUDRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1).isValid)
    }
}
