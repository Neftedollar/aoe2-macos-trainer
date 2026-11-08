import Foundation
import XCTest
@testable import AoE2MacTrainer

final class BuildOrderTests: XCTestCase {
    func testBundledBuildsHaveUniqueIDsAndSteps() {
        let builds = BuildOrderLibrary.bundled()
        XCTAssertGreaterThanOrEqual(builds.count, 5)
        XCTAssertEqual(Set(builds.map(\.id)).count, builds.count)
        XCTAssertTrue(builds.allSatisfy { !$0.steps.isEmpty })
        XCTAssertTrue(builds.contains { $0.civilization == "Португальцы" })
        XCTAssertTrue(builds.contains { $0.civilization == "Испанцы" })
    }

    func testDuplicateIDsAreRejected() throws {
        let build = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let data = try JSONEncoder().encode([build, build])
        XCTAssertThrowsError(try BuildOrderLibrary.decode(data))
    }

    @MainActor
    func testStepNavigationClampsAndBuildSwitchResets() {
        let state = TrainerState()
        for _ in 0..<100 { state.next() }
        XCTAssertEqual(state.stepIndex, (state.selectedBuild?.steps.count ?? 1) - 1)
        state.previous()
        XCTAssertEqual(state.stepIndex, (state.selectedBuild?.steps.count ?? 2) - 2)
        state.cycleBuild()
        XCTAssertEqual(state.stepIndex, 0)
        XCTAssertEqual(state.selectedBuildIndex, 1)
    }
}
