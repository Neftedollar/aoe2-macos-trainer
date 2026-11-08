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
}
