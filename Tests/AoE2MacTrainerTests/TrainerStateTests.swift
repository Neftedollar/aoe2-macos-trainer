import Foundation
import XCTest
@testable import AoE2MacTrainer

final class TrainerStateTests: XCTestCase {
    private enum FixtureError: Error { case unavailable }

    private func build(_ id: String, civilizations: [String],
                       steps: [BuildStep]? = nil) -> BuildOrder {
        BuildOrder(id: id, name: id, civilizations: civilizations, map: "Arena",
                   strategy: "Training", description: "State test fixture",
                   steps: steps ?? [BuildStep(action: "Start", targetTimeSeconds: 0),
                                    BuildStep(action: "Next", targetTimeSeconds: 60)])
    }

    @MainActor
    func testStartupUnknownCivilizationDoesNotExposeTheWholeCatalog() {
        let catalog = [build("port", civilizations: ["portuguese"]),
                       build("frank", civilizations: ["franks"])]
        let state = TrainerState(builds: catalog)
        XCTAssertEqual(state.catalog, catalog)
        XCTAssertNil(state.previewCivilizationID)
        XCTAssertNil(state.previewCivilization)
        XCTAssertTrue(state.builds.isEmpty)
        XCTAssertNil(state.selectedBuild)
        XCTAssertNil(state.selectedStep)
        state.cycleBuild()
        state.next()
        state.previous()
        XCTAssertTrue(state.builds.isEmpty)
        XCTAssertNil(state.selectedBuild)
        XCTAssertEqual(state.stepIndex, 0)
    }

    @MainActor
    func testUnknownAndNoMatchCivilizationsFailClosed() {
        let state = TrainerState(builds: [build("port", civilizations: ["portuguese"])])
        state.selectPreviewCivilization("turks")
        XCTAssertEqual(state.previewCivilizationID, "turks")
        XCTAssertTrue(state.builds.isEmpty)
        state.cycleBuild()
        XCTAssertNil(state.selectedBuild)

        state.selectPreviewCivilization("not-a-civilization")
        XCTAssertNil(state.previewCivilizationID)
        XCTAssertTrue(state.builds.isEmpty)
        state.cycleBuild()
        XCTAssertNil(state.selectedBuild)

        state.selectPreviewCivilization("Portuguese")
        XCTAssertEqual(state.selectedBuild?.id, "port")
        state.selectPreviewCivilization(nil)
        XCTAssertTrue(state.builds.isEmpty)
        XCTAssertNil(state.selectedBuild)
    }

    @MainActor
    func testCycleOnlyVisitsCompatiblePreviewBuilds() {
        let catalog = [build("port", civilizations: ["portuguese"]),
                       build("frank", civilizations: ["franks"]),
                       build("shared", civilizations: ["portuguese", "armenians"]),
                       build("georgian", civilizations: ["georgians"])]
        let state = TrainerState(builds: catalog)
        state.selectPreviewCivilization("Португальцы")
        XCTAssertEqual(state.previewCivilizationID, "portuguese")
        XCTAssertEqual(state.builds.map(\.id), ["port", "shared"])
        XCTAssertTrue(state.builds.allSatisfy { $0.civilizations == ["portuguese"] })
        XCTAssertEqual(state.selectedBuild?.id, "port")

        state.next()
        state.cycleBuild()
        XCTAssertEqual(state.selectedBuild?.id, "shared")
        XCTAssertEqual(state.stepIndex, 0)
        state.cycleBuild()
        XCTAssertEqual(state.selectedBuild?.id, "port")
        state.selectBuild(999)
        XCTAssertEqual(state.selectedBuild?.id, "port")
        XCTAssertEqual(state.catalog, catalog, "Preview must not narrow the export catalog")
    }

    @MainActor
    func testTurksPreviewExcludesConditionalStepsWithoutChangingOriginals() {
        let steps = [
            BuildStep(action: "Start", targetTimeSeconds: 0),
            BuildStep(action: "Pikemen", targetTimeSeconds: 100, exclude: ["turks"]),
            BuildStep(action: "Portuguese-only", targetTimeSeconds: 200,
                      includeOnly: ["portuguese"]),
            BuildStep(action: "Common finish", targetTimeSeconds: 300)
        ]
        let original = build("conditional", civilizations: ["turks", "portuguese"], steps: steps)
        let state = TrainerState(builds: [original])
        state.selectPreviewCivilization("turks")
        XCTAssertEqual(state.selectedBuild?.steps.map(\.action), ["Start", "Common finish"])
        XCTAssertTrue(state.selectedBuild?.steps.allSatisfy {
            $0.includeOnly == nil && $0.exclude == nil
        } ?? false)
        for _ in 0..<100 { state.next() }
        XCTAssertEqual(state.stepIndex, 1)
        state.previous()
        XCTAssertEqual(state.stepIndex, 0)

        state.selectPreviewCivilization("portuguese")
        XCTAssertEqual(state.selectedBuild?.steps.map(\.action), steps.map(\.action))
        XCTAssertEqual(state.catalog, [original])
        XCTAssertEqual(state.catalog.first?.steps[1].exclude, ["turks"])
    }

    @MainActor
    func testCivilizationSwitchRetainsCompatibleBuildButResetsStep() {
        let state = TrainerState(builds: [
            build("port", civilizations: ["portuguese"]),
            build("shared", civilizations: ["portuguese", "armenians"]),
            build("armenian", civilizations: ["armenians"])
        ])
        state.selectPreviewCivilization("portuguese")
        state.selectBuild(1)
        state.next()
        XCTAssertEqual(state.stepIndex, 1)
        state.selectPreviewCivilization("armenians")
        XCTAssertEqual(state.builds.map(\.id), ["shared", "armenian"])
        XCTAssertEqual(state.selectedBuild?.id, "shared")
        XCTAssertEqual(state.selectedBuildIndex, 0)
        XCTAssertEqual(state.stepIndex, 0)

        state.selectBuild(1)
        state.next()
        state.selectPreviewCivilization("portuguese")
        XCTAssertEqual(state.selectedBuild?.id, "port", "Unsupported old selection must not survive")
        XCTAssertEqual(state.stepIndex, 0)
    }

    @MainActor
    func testReloadRecomputesEligibilityAndKeepsSelectedIDWhenSupported() throws {
        let old = [build("port", civilizations: ["portuguese"]),
                   build("shared", civilizations: ["portuguese", "armenians"])]
        let replacement = [build("frank", civilizations: ["franks"]),
                           build("shared", civilizations: ["portuguese", "armenians"],
                                 steps: [BuildStep(action: "Updated", targetTimeSeconds: 0)]),
                           build("another-port", civilizations: ["portuguese"])]
        let state = TrainerState(builds: old, loader: { replacement })
        state.selectPreviewCivilization("portuguese")
        state.selectBuild(1)
        state.next()
        try state.reloadBuilds()
        XCTAssertEqual(state.catalog, replacement)
        XCTAssertEqual(state.builds.map(\.id), ["shared", "another-port"])
        XCTAssertEqual(state.selectedBuild?.id, "shared")
        XCTAssertEqual(state.selectedStep?.action, "Updated")
        XCTAssertEqual(state.previewCivilizationID, "portuguese")
        XCTAssertEqual(state.stepIndex, 0)
        XCTAssertNil(state.loadErrorMessage)
    }

    @MainActor
    func testInvalidReloadIsAtomicAndLeavesNavigationIntact() {
        let initial = [build("port", civilizations: ["portuguese"])]
        let invalid = [build("bad", civilizations: ["not-a-civilization"])]
        let state = TrainerState(builds: initial, loader: { invalid })
        state.selectPreviewCivilization("portuguese")
        state.next()
        let visibleBefore = state.builds
        XCTAssertThrowsError(try state.reloadBuilds())
        XCTAssertEqual(state.catalog, initial)
        XCTAssertEqual(state.builds, visibleBefore)
        XCTAssertEqual(state.previewCivilizationID, "portuguese")
        XCTAssertEqual(state.selectedBuild?.id, "port")
        XCTAssertEqual(state.stepIndex, 1)
        XCTAssertNotNil(state.loadErrorMessage)
    }

    @MainActor
    func testReloadAfterBuildRemovedCanHaveNoMatchWithoutFallingBackToAll() throws {
        let initial = [build("port", civilizations: ["portuguese"])]
        let replacement = [build("frank", civilizations: ["franks"])]
        let state = TrainerState(builds: initial, loader: { replacement })
        state.selectPreviewCivilization("portuguese")
        try state.reloadBuilds()
        XCTAssertEqual(state.catalog, replacement)
        XCTAssertEqual(state.previewCivilizationID, "portuguese")
        XCTAssertTrue(state.builds.isEmpty)
        state.cycleBuild()
        XCTAssertNil(state.selectedBuild)
    }

    @MainActor
    func testStartupLoadFailureIsVisibleWithoutBundledFallbackAndCanRecover() throws {
        let replacement = [build("port", civilizations: ["portuguese"])]
        var unavailable = true
        let state = TrainerState(loader: {
            if unavailable { throw FixtureError.unavailable }
            return replacement
        })
        XCTAssertNotNil(state.loadErrorMessage)
        XCTAssertTrue(state.catalog.isEmpty)
        XCTAssertTrue(state.builds.isEmpty)
        unavailable = false
        try state.reloadBuilds()
        XCTAssertNil(state.loadErrorMessage)
        XCTAssertEqual(state.catalog, replacement)
        XCTAssertTrue(state.builds.isEmpty, "Successful load still must not guess the user's civ")
        state.selectPreviewCivilization("portuguese")
        XCTAssertEqual(state.selectedBuild?.id, "port")
    }

    @MainActor
    func testInvalidInjectedStartupCatalogIsNotPublished() {
        let state = TrainerState(builds: [build("bad", civilizations: ["not-a-civilization"])])
        XCTAssertNotNil(state.loadErrorMessage)
        XCTAssertTrue(state.catalog.isEmpty)
        XCTAssertNil(state.selectedBuild)
    }
}
