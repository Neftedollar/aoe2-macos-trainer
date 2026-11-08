import Foundation
import XCTest
@testable import AoE2MacTrainer

final class BuildOrderTests: XCTestCase {
    func testBundledBuildsHaveUniqueIDsAndSteps() {
        let builds = BuildOrderLibrary.bundled()
        XCTAssertGreaterThanOrEqual(builds.count, 10)
        XCTAssertEqual(Set(builds.map(\.id)).count, builds.count)
        XCTAssertTrue(builds.allSatisfy { !$0.steps.isEmpty })
        XCTAssertTrue(builds.contains { $0.civilization == "Португальцы" })
        XCTAssertTrue(builds.contains { $0.civilization == "Испанцы" })
        XCTAssertTrue(builds.contains { $0.civilizations == ["Армяне", "Грузины"] })
    }

    func testMultipleCivilizationsRoundTrip() throws {
        let original = try XCTUnwrap(BuildOrderLibrary.bundled().first {
            $0.civilizations == ["Армяне", "Грузины"]
        })
        let decoded = try BuildOrderLibrary.decode(JSONEncoder().encode([original]))
        XCTAssertEqual(decoded[0].civilizations, ["Армяне", "Грузины"])
        XCTAssertEqual(decoded[0].civilization, "Армяне, Грузины")
    }

    func testOldStringCivilizationJSONStillLoads() throws {
        let legacy = """
        [{"id":"old","name":"Old","civilization":"Португальцы","map":"Арена",
          "strategy":"Fast Castle","description":"Old format","steps":[{"action":"Start","targetTimeSeconds":0}]}]
        """
        let build = try XCTUnwrap(BuildOrderLibrary.decode(Data(legacy.utf8)).first)
        XCTAssertEqual(build.civilizations, ["Португальцы"])
    }

    func testUnsafeMapScriptFileIsRejected() throws {
        let original = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let invalid = BuildOrder(
            id: "unsafe-map", name: "Unsafe", civilizations: ["Любая"], map: "Арена",
            mapScriptFile: "../Arena.rms", strategy: "FC", description: "", steps: original.steps
        )
        XCTAssertThrowsError(try BuildOrderLibrary.decode(JSONEncoder().encode([invalid])))
    }

    func testDuplicateIDsAreRejected() throws {
        let build = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let data = try JSONEncoder().encode([build, build])
        XCTAssertThrowsError(try BuildOrderLibrary.decode(data))
    }

    func testInvalidGoalIDsAndCountsAreRejected() throws {
        let original = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let invalid = BuildOrder(
            id: "bad-goals", name: "Bad Goals", civilization: original.civilization,
            map: original.map, strategy: original.strategy, description: "",
            steps: [BuildStep(
                action: "Impossible goal", targetTimeSeconds: 600,
                allocation: ResourceAllocation(food: -1, wood: 1, gold: 0, stone: 0),
                unitGoals: [UnitGoal(objectId: -1, count: 1, label: "Stable")]
            )]
        )
        XCTAssertThrowsError(try BuildOrderLibrary.decode(JSONEncoder().encode([invalid])))
        XCTAssertThrowsError(try XSBuildExporter.generate(for: invalid))
    }

    func testDuplicateUnitGoalsAreRejected() throws {
        let original = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let duplicate = BuildOrder(
            id: "duplicate-goal", name: "Duplicate", civilization: original.civilization,
            map: original.map, strategy: original.strategy, description: "",
            steps: [BuildStep(
                action: "Two entries for the same object", targetTimeSeconds: 600,
                unitGoals: [UnitGoal(objectId: 101, count: 1, label: "Stable"),
                            UnitGoal(objectId: 101, count: 2, label: "Stable")]
            )]
        )
        XCTAssertThrowsError(try BuildOrderLibrary.decode(JSONEncoder().encode([duplicate])))
    }

    func testChronologicalGoalsMustBeOrdered() throws {
        let original = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let unordered = BuildOrder(
            id: "unordered", name: "Unordered", civilization: original.civilization,
            map: original.map, strategy: original.strategy, description: "",
            steps: [BuildStep(action: "Second", targetTimeSeconds: 600),
                    BuildStep(action: "First", targetTimeSeconds: 120)]
        )
        XCTAssertThrowsError(try BuildOrderLibrary.decode(JSONEncoder().encode([unordered])))
    }

    func testCustomBuildOverridesBundledID() throws {
        let original = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let custom = BuildOrder(
            id: original.id, name: "Custom", civilization: original.civilization,
            map: original.map, strategy: original.strategy, description: "",
            steps: original.steps
        )
        let merged = BuildOrderLibrary.merged(bundled: [original], custom: [custom])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "Custom")
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
