import Foundation
import XCTest
@testable import AoE2MacTrainer

final class TrainingClockTests: XCTestCase {
    func testNormalSpeedAccountsForGameTime() {
        var clock = TrainingClock()
        let origin = Date(timeIntervalSince1970: 1_000)
        clock.toggle(at: origin)
        XCTAssertEqual(clock.seconds(at: origin.addingTimeInterval(10)), 17)
    }

    func testPauseResumeAndReset() {
        var clock = TrainingClock()
        let origin = Date(timeIntervalSince1970: 1_000)
        clock.toggle(at: origin)
        clock.toggle(at: origin.addingTimeInterval(10))
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.seconds(at: origin.addingTimeInterval(50)), 17)

        clock.toggle(at: origin.addingTimeInterval(50))
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.seconds(at: origin.addingTimeInterval(60)), 34)

        clock.reset(at: origin.addingTimeInterval(60))
        XCTAssertEqual(clock.seconds(at: origin.addingTimeInterval(60)), 0)
        XCTAssertTrue(clock.isRunning)
    }
}
