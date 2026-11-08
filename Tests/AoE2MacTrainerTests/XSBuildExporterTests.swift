import Foundation
import XCTest
@testable import AoE2MacTrainer

final class XSBuildExporterTests: XCTestCase {
    func testBundledBuildsGenerateStandaloneScriptWithTargets() throws {
        for build in BuildOrderLibrary.bundled() {
            let script = try XSBuildExporter.generate(for: build)
            XCTAssertFalse(script.contains("// @PLAN_SETUP@"))
            XCTAssertTrue(script.contains("trainerMetrics"))
            XCTAssertTrue(script.contains("xsPlayerAttribute(player, 166)"))
            XCTAssertTrue(script.contains("xsDisplayInstructions"))
            XCTAssertTrue(script.contains("trainerStepCount = \(build.steps.count)"))
            XCTAssertTrue(script.contains("xsArraySetString(trainerStepLabels"))
            XCTAssertTrue(script.contains("trainerStepDoneTimes"))
            XCTAssertTrue(script.contains("trainerTrackGoals"))
            XCTAssertTrue(script.contains("trainerGoalProgress"))
            XCTAssertTrue(script.contains("xsGetObjectCount"))
        }
    }

    func testBuildNameAndStepAreEscaped() throws {
        let original = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let synthetic = BuildOrder(
            id: "test-custom", name: "\"Test\"", civilization: original.civilization,
            map: original.map, strategy: original.strategy, description: "",
            steps: [BuildStep(action: "Use \"quoted\" command", targetVillagers: 3,
                              targetTimeSeconds: 10, allocation: nil, note: nil)]
        )
        let script = try XSBuildExporter.generate(for: synthetic)
        XCTAssertTrue(script.contains("\\\"Test\\\""))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepTimes, 0, 10)"))
        XCTAssertEqual(XSBuildExporter.recommendedFileName(for: synthetic), "aoe2trainer_test-custom.xs")
    }

    func testUnitAndWorkerTargetsAreEmbeddedIntoXS() throws {
        let original = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let synthetic = BuildOrder(
            id: "goal-demo", name: "Goal Demo", civilization: original.civilization,
            map: original.map, strategy: original.strategy, description: "",
            steps: [BuildStep(
                action: "6 on food, one stable by 10:00", targetVillagers: 12,
                targetTimeSeconds: 600,
                allocation: ResourceAllocation(food: 6, wood: 4, gold: 0, stone: 0),
                unitGoals: [UnitGoal(objectId: 101, count: 1, label: "Stable")]
            )]
        )
        let script = try XSBuildExporter.generate(for: synthetic)
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepTimes, 0, 600)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepFood, 0, 6)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepWood, 0, 4)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerUnitGoalObjects, 0, 101)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerUnitGoalCounts, 0, 1)"))
        XCTAssertTrue(script.contains("xsArraySetString(trainerUnitGoalLabels, 0, \"Stable\")"))
    }
}
