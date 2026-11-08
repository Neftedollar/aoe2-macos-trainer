import Foundation
import XCTest
@testable import AoE2MacTrainer

final class TrainerStateTests: XCTestCase {
    private enum FixtureError: Error { case unavailable }

    private func build(_ id: String, civilizations: [String],
                       steps: [BuildStep]? = nil, family: String? = nil,
                       food: [StartingFoodRequirement]? = nil) -> BuildOrder {
        BuildOrder(id: id, name: id, civilizations: civilizations, map: "Arena",
                   strategy: "Training", description: "State test fixture",
                   steps: steps ?? [BuildStep(action: "Start", targetTimeSeconds: 0),
                                    BuildStep(action: "Next", targetTimeSeconds: 60)],
                   strategyFamily: family, startingFoodRequirements: food)
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
        XCTAssertNil(state.selectedBuild, "An unrelated legacy plan must not silently replace intent")
        XCTAssertEqual(state.requestedBuildID, "armenian")
        XCTAssertEqual(state.stepIndex, 0)
        state.cycleBuild()
        XCTAssertEqual(state.selectedBuild?.id, "port", "Explicit cycling can choose another eligible plan")
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
        let evidence = StartingFoodEvidence(pushableHuntCount: 3, smallGameCount: 2)
        state.updatePreviewFoodEvidence(evidence)
        state.next()
        let visibleBefore = state.builds
        XCTAssertThrowsError(try state.reloadBuilds())
        XCTAssertEqual(state.catalog, initial)
        XCTAssertEqual(state.builds, visibleBefore)
        XCTAssertEqual(state.previewCivilizationID, "portuguese")
        XCTAssertEqual(state.previewFoodEvidence, evidence)
        XCTAssertEqual(state.requestedBuildID, "port")
        XCTAssertEqual(state.requestedStrategyFamily, "port")
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

    @MainActor
    func testFoodDiscoveryAddsVariantsWithoutReplacingSelectedBuildOrStep() {
        let catalog = [
            build("fc-deer", civilizations: ["portuguese"], family: "fast-castle",
                  food: [StartingFoodRequirement(kind: .pushableHunt, minCount: 3)]),
            build("fc-mixed", civilizations: ["portuguese"], family: "fast-castle",
                  food: [StartingFoodRequirement(kind: .pushableHunt, minCount: 3),
                         StartingFoodRequirement(kind: .smallGame, minCount: 2)]),
            build("fc-generic", civilizations: ["portuguese"], family: "fast-castle"),
            build("fi-generic", civilizations: ["portuguese"], family: "fast-imperial")
        ]
        let state = TrainerState(builds: catalog)
        state.selectPreviewCivilization("portuguese")
        XCTAssertEqual(state.selectedBuild?.id, "fc-generic")
        state.next()
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3))
        XCTAssertEqual(state.builds.map(\.id), ["fc-deer", "fc-generic", "fi-generic"])
        XCTAssertEqual(state.selectedBuild?.id, "fc-generic")
        XCTAssertEqual(state.selectedBuildIndex, 1)
        XCTAssertEqual(state.stepIndex, 1)

        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3, smallGameCount: 2))
        XCTAssertEqual(state.builds.map(\.id), ["fc-deer", "fc-mixed", "fc-generic", "fi-generic"])
        XCTAssertEqual(state.selectedBuild?.id, "fc-generic")
        XCTAssertEqual(state.stepIndex, 1)
        XCTAssertEqual(state.catalog, catalog)
    }

    @MainActor
    func testLowerManualFoodMakesRequestedPlanUnavailableWithoutSwitchingFamily() {
        let state = TrainerState(builds: [
            build("fi-first", civilizations: ["portuguese"], family: "fast-imperial"),
            build("fc-deer", civilizations: ["portuguese"], family: "fast-castle",
                  food: [StartingFoodRequirement(kind: .pushableHunt, minCount: 3)]),
            build("fc-generic", civilizations: ["portuguese"], family: "fast-castle")
        ])
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3))
        state.selectPreviewCivilization("portuguese")
        state.selectBuild(1)
        state.next()
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 2))
        XCTAssertEqual(state.builds.map(\.id), ["fi-first", "fc-generic"])
        XCTAssertNil(state.selectedBuild)
        XCTAssertNil(state.selectedStep)
        XCTAssertEqual(state.requestedBuildID, "fc-deer")
        XCTAssertEqual(state.requestedStrategyFamily, "fast-castle")
        XCTAssertEqual(state.unavailableRequestedBuild?.name, "fc-deer")
        XCTAssertEqual(state.exportPreferredBuildID, "fc-deer")

        state.next()
        state.previous()
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3))
        XCTAssertEqual(state.selectedBuild?.id, "fc-deer")
        XCTAssertEqual(state.stepIndex, 1, "Re-qualifying the same plan should restore the saved step")
    }

    @MainActor
    func testExplicitCycleCanLeaveUnavailableFamilyButDiscoveryCannotUndoIt() {
        let state = TrainerState(builds: [
            build("fc-deer", civilizations: ["portuguese"], family: "fast-castle",
                  food: [StartingFoodRequirement(kind: .pushableHunt, minCount: 3)]),
            build("fi-generic", civilizations: ["portuguese"], family: "fast-imperial")
        ])
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3))
        state.selectPreviewCivilization("portuguese")
        XCTAssertEqual(state.selectedBuild?.id, "fc-deer")
        state.updatePreviewFoodEvidence(.unknown)
        XCTAssertNil(state.selectedBuild)
        XCTAssertEqual(state.builds.map(\.id), ["fi-generic"])
        state.cycleBuild()
        state.next()
        XCTAssertEqual(state.selectedBuild?.id, "fi-generic")
        XCTAssertEqual(state.requestedStrategyFamily, "fast-imperial")
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 6))
        XCTAssertEqual(state.selectedBuild?.id, "fi-generic")
        XCTAssertEqual(state.stepIndex, 1)
    }

    @MainActor
    func testNewlyQualifiedPlanRequiresExplicitSelectionWhenNoIntentExists() {
        let state = TrainerState(builds: [
            build("fc-deer", civilizations: ["portuguese"], family: "fast-castle",
                  food: [StartingFoodRequirement(kind: .pushableHunt, minCount: 3)])
        ])
        state.selectPreviewCivilization("portuguese")
        XCTAssertTrue(state.builds.isEmpty)
        XCTAssertNil(state.requestedBuildID)
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3))
        XCTAssertEqual(state.builds.map(\.id), ["fc-deer"])
        XCTAssertNil(state.selectedBuild)
        state.cycleBuild()
        XCTAssertEqual(state.selectedBuild?.id, "fc-deer")
    }

    @MainActor
    func testFoodKindsRemainIndependentAndZeroDoesNotAssertAbsence() {
        let state = TrainerState(builds: [
            build("deer", civilizations: ["portuguese"],
                  food: [StartingFoodRequirement(kind: .pushableHunt, minCount: 3)]),
            build("small", civilizations: ["portuguese"],
                  food: [StartingFoodRequirement(kind: .smallGame, minCount: 3)]),
            build("generic", civilizations: ["portuguese"])
        ])
        state.selectPreviewCivilization("portuguese")
        XCTAssertEqual(state.previewFoodEvidence, .unknown)
        XCTAssertEqual(state.builds.map(\.id), ["generic"])
        state.updatePreviewFoodEvidence(StartingFoodEvidence(smallGameCount: 3))
        XCTAssertEqual(state.builds.map(\.id), ["small", "generic"])
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3))
        XCTAssertEqual(state.builds.map(\.id), ["deer", "generic"])
        state.updatePreviewFoodEvidence(.unknown)
        XCTAssertEqual(state.builds.map(\.id), ["generic"])
    }

    @MainActor
    func testCivilizationSwitchPreservesRequestedFamilyInsteadOfChoosingEarlierFI() {
        let state = TrainerState(builds: [
            build("port-fc", civilizations: ["portuguese"], family: "fast-castle"),
            build("armenian-fi", civilizations: ["armenians"], family: "fast-imperial"),
            build("armenian-fc", civilizations: ["armenians"], family: "fast-castle")
        ])
        state.selectPreviewCivilization("portuguese")
        state.next()
        state.selectPreviewCivilization("armenians")
        XCTAssertEqual(state.selectedBuild?.id, "armenian-fc")
        XCTAssertEqual(state.requestedStrategyFamily, "fast-castle")
        XCTAssertEqual(state.stepIndex, 0)
        XCTAssertTrue(state.selectionNotice?.contains("port-fc") ?? false)
        XCTAssertTrue(state.selectionNotice?.contains("armenian-fc") ?? false)
        XCTAssertTrue(state.selectionNotice?.contains("не подходит") ?? false)
        state.updatePreviewFoodEvidence(StartingFoodEvidence(smallGameCount: 2))
        XCTAssertNotNil(state.selectionNotice, "New food evidence must not hide a fallback explanation")
        state.selectBuild(1)
        XCTAssertNil(state.selectionNotice, "An explicit selection acknowledges the chosen plan")
    }

    @MainActor
    func testUnconfirmedFoodVariantRemainsPendingAfterReloadOrCompatibleCivChange() throws {
        let catalog = [
            build("fc-deer", civilizations: ["portuguese", "turks"], family: "fast-castle",
                  food: [StartingFoodRequirement(kind: .pushableHunt, minCount: 3)]),
            build("fc-generic", civilizations: ["portuguese", "turks"], family: "fast-castle")
        ]
        let state = TrainerState(builds: catalog, loader: { catalog })
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3))
        state.selectPreviewCivilization("portuguese")
        XCTAssertEqual(state.selectedBuild?.id, "fc-deer")
        state.updatePreviewFoodEvidence(.unknown)
        XCTAssertNil(state.selectedBuild)

        try state.reloadBuilds()
        XCTAssertNil(state.selectedBuild, "Reload must not silently switch a food-pending request")
        XCTAssertEqual(state.requestedBuildID, "fc-deer")
        XCTAssertNil(state.selectionNotice)

        state.selectPreviewCivilization("turks")
        XCTAssertNil(state.selectedBuild, "Civ compatibility does not compensate for missing food evidence")
        XCTAssertEqual(state.requestedBuildID, "fc-deer")
        XCTAssertEqual(state.exportPreferredBuildID, "fc-deer")
        XCTAssertEqual(state.builds.map(\.id), ["fc-generic"])
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3))
        XCTAssertEqual(state.selectedBuild?.id, "fc-deer")
    }

    @MainActor
    func testCatalogRemovalSameFamilyFallbackHasVisibleExplanation() throws {
        let initial = [build("old-fc", civilizations: ["portuguese"], family: "fast-castle")]
        let replacement = [
            build("fi", civilizations: ["portuguese"], family: "fast-imperial"),
            build("new-fc", civilizations: ["portuguese"], family: "fast-castle")
        ]
        let state = TrainerState(builds: initial, loader: { replacement })
        state.selectPreviewCivilization("portuguese")
        try state.reloadBuilds()
        XCTAssertEqual(state.selectedBuild?.id, "new-fc")
        XCTAssertEqual(state.exportPreferredBuildID, "new-fc")
        XCTAssertTrue(state.selectionNotice?.contains("old-fc") ?? false)
        XCTAssertTrue(state.selectionNotice?.contains("new-fc") ?? false)
        XCTAssertTrue(state.selectionNotice?.contains("больше нет в каталоге") ?? false)
    }

    @MainActor
    func testReloadDoesNotSilentlyReplaceRemovedFamilyWithAnother() throws {
        let initial = [build("fc", civilizations: ["portuguese"], family: "fast-castle")]
        let replacement = [build("fi", civilizations: ["portuguese"], family: "fast-imperial")]
        let state = TrainerState(builds: initial, loader: { replacement })
        state.selectPreviewCivilization("portuguese")
        try state.reloadBuilds()
        XCTAssertEqual(state.builds.map(\.id), ["fi"])
        XCTAssertNil(state.selectedBuild)
        XCTAssertEqual(state.requestedStrategyFamily, "fast-castle")
        XCTAssertNil(state.exportPreferredBuildID, "Do not export a stale ID removed from the catalog")
        state.cycleBuild()
        XCTAssertEqual(state.selectedBuild?.id, "fi")
    }

    @MainActor
    func testResetWhilePlanUnavailableClearsItsSavedStep() {
        let state = TrainerState(builds: [
            build("deer", civilizations: ["portuguese"],
                  food: [StartingFoodRequirement(kind: .pushableHunt, minCount: 3)])
        ])
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3))
        state.selectPreviewCivilization("portuguese")
        state.next()
        state.updatePreviewFoodEvidence(.unknown)
        state.reset()
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: 3))
        XCTAssertEqual(state.selectedBuild?.id, "deer")
        XCTAssertEqual(state.stepIndex, 0)
    }

    @MainActor
    func testManualEvidenceIsBoundedAndNeverMutatesExportCatalog() throws {
        let catalog = [
            build("fc-generic", civilizations: ["portuguese"], family: "fast-castle"),
            build("fc-deer", civilizations: ["portuguese"], family: "fast-castle",
                  food: [StartingFoodRequirement(kind: .pushableHunt, minCount: 3)])
        ]
        let state = TrainerState(builds: catalog)
        state.selectPreviewCivilization("portuguese")
        let before = try XSBuildExporter.generate(builds: state.catalog,
                                                  preferredBuildID: state.exportPreferredBuildID)
        state.updatePreviewFoodEvidence(StartingFoodEvidence(pushableHuntCount: .max, smallGameCount: -1))
        XCTAssertEqual(state.previewFoodEvidence.pushableHuntCount, 32)
        XCTAssertEqual(state.previewFoodEvidence.smallGameCount, 0)
        XCTAssertEqual(state.catalog, catalog)
        XCTAssertEqual(state.exportPreferredBuildID, "fc-generic")
        let after = try XSBuildExporter.generate(builds: state.catalog,
                                                 preferredBuildID: state.exportPreferredBuildID)
        XCTAssertEqual(after, before, "Manual preview facts must never leak into exported XS")
    }
}
