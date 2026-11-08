import XCTest
@testable import AoE2MacTrainer

final class StartingFoodEvidenceTests: XCTestCase {
    func testUnknownEvidenceQualifiesOnlyFoodIndependentPlans() {
        let unknown = StartingFoodEvidence.unknown
        XCTAssertEqual(unknown.observedCount(for: .pushableHunt), 0)
        XCTAssertEqual(unknown.observedCount(for: .smallGame), 0)
        XCTAssertTrue(unknown.satisfies(requirements: []))
        XCTAssertFalse(unknown.satisfies(requirements: [.init(kind: .pushableHunt, minCount: 1)]))
        XCTAssertFalse(unknown.satisfies(requirements: [.init(kind: .smallGame, minCount: 1)]))
    }

    func testRequirementsUsePositiveANDAtTheExactThreshold() {
        let requirements: [StartingFoodRequirement] = [
            .init(kind: .pushableHunt, minCount: 3), .init(kind: .smallGame, minCount: 2)
        ]
        XCTAssertFalse(StartingFoodEvidence(pushableHuntCount: 3).satisfies(requirements: requirements))
        XCTAssertFalse(StartingFoodEvidence(pushableHuntCount: 3, smallGameCount: 1).satisfies(requirements: requirements))
        XCTAssertTrue(StartingFoodEvidence(pushableHuntCount: 3, smallGameCount: 2).satisfies(requirements: requirements))
    }

    func testSmallGameObservationsDoNotProveHuntAbsentOrSatisfyHuntRequirements() {
        let smallGame = StartingFoodEvidence(smallGameCount: 6)
        XCTAssertFalse(smallGame.satisfies(requirements: [.init(kind: .pushableHunt, minCount: 1)]))
        let both = smallGame.merging(StartingFoodEvidence(pushableHuntCount: 3))
        XCTAssertEqual(both.smallGameCount, 6)
        XCTAssertTrue(both.satisfies(requirements: [.init(kind: .pushableHunt, minCount: 3)]))
        XCTAssertTrue(both.satisfies(requirements: [.init(kind: .smallGame, minCount: 6)]))
    }

    func testMergingCumulativeSnapshotsDoesNotDoubleCountOrForgetConsumedAnimals() {
        let initial = StartingFoodEvidence(pushableHuntCount: 3, smallGameCount: 2)
        XCTAssertEqual(initial.merging(initial), initial)
        XCTAssertEqual(initial.merging(.unknown), initial)
        XCTAssertEqual(initial.merging(StartingFoodEvidence(pushableHuntCount: 1, smallGameCount: 1)), initial)
        XCTAssertEqual(initial.merging(StartingFoodEvidence(pushableHuntCount: 4)),
                       StartingFoodEvidence(pushableHuntCount: 4, smallGameCount: 2))
        // Reset by creating a NEW match's value, not by merging zeroes into the old one.
        XCTAssertNotEqual(initial, StartingFoodEvidence.unknown)
    }

    func testInvalidEvidenceAndRequirementsFailClosed() {
        XCTAssertEqual(StartingFoodEvidence(pushableHuntCount: -5, smallGameCount: -1), .unknown)
        let evidence = StartingFoodEvidence(pushableHuntCount: 100)
        for count in [-1, 0, 33] {
            XCTAssertFalse(evidence.satisfies(requirements: [.init(kind: .pushableHunt, minCount: count)]))
        }
        XCTAssertFalse(evidence.satisfies(requirements: [
            .init(kind: .pushableHunt, minCount: 1), .init(kind: .pushableHunt, minCount: 3)
        ]))
    }
}
