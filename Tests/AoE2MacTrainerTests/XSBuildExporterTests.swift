import Foundation
import XCTest
@testable import AoE2MacTrainer

/// These tests validate the exported source and compiler mapping. They do not
/// replace compiling or running XS in the user's actual AoE2 Mac game build.
final class XSBuildExporterTests: XCTestCase {
    private func build(
        id: String = "test-plan",
        name: String = "Test plan",
        civilizations: [String] = ["portuguese"],
        steps: [BuildStep] = [BuildStep(action: "Reach 6 villagers", targetVillagers: 6, targetTimeSeconds: 75)],
        strategyFamily: String? = nil,
        startingFoodRequirements: [StartingFoodRequirement]? = nil
    ) -> BuildOrder {
        BuildOrder(id: id, name: name, civilizations: civilizations,
                   map: "Арена", strategy: "Fast Castle", description: "Test fixture", steps: steps,
                   strategyFamily: strategyFamily, startingFoodRequirements: startingFoodRequirements)
    }

    func testBundledCatalogUsesRuntimeCivilizationAndStrictFiltering() throws {
        let builds = try BuildOrderLibrary.bundled()
        XCTAssertFalse(builds.isEmpty)
        let script = try XSBuildExporter.generate(builds: builds)
        XCTAssertFalse(script.contains("// @CATALOG_SETUP@"))
        XCTAssertFalse(script.contains("// @FOOD_OBSERVER@"))
        XCTAssertTrue(script.contains("trainerBuildCount = \(builds.count);"))
        XCTAssertTrue(script.contains("xsUnsyncGetLocalPlayerId()"))
        XCTAssertTrue(script.contains("xsGetPlayerCivilization(player)"))
        XCTAssertTrue(script.contains("xsGetPlayerCivName(player, true)"))
        XCTAssertTrue(script.contains("NO MATCHING BUILDS"))
        XCTAssertTrue(script.contains("trainerSelectBuildSlot(-1);"))
        XCTAssertTrue(script.contains("xsArrayGetInt(trainerAllowedCivilizations, allowedIndex) == civilization"))
        XCTAssertFalse(script.contains("xsSetPlayerAttribute("))
        XCTAssertFalse(script.contains("xsCreateUnit("))
        XCTAssertFalse(script.contains("xsEffectAmount("))
        XCTAssertTrue(script.unicodeScalars.allSatisfy { $0.value < 128 })
        XCTAssertTrue(script.contains("trainerUsesASCIIText = true;"))
    }

    func testSingleBuildExporterRetainsMetricsAndTargets() throws {
        let plan = build()
        let script = try XSBuildExporter.generate(for: plan)
        XCTAssertTrue(script.contains("trainerBuildCount = 1;"))
        XCTAssertTrue(script.contains("trainerPreferredBuild = 0;"))
        XCTAssertTrue(script.contains("trainerMetrics"))
        XCTAssertTrue(script.contains("xsPlayerAttribute(player, 166)"))
        XCTAssertTrue(script.contains("xsDisplayInstructions"))
        XCTAssertTrue(script.contains("trainerTrackGoals"))
        XCTAssertTrue(script.contains("trainerGoalProgress"))
        XCTAssertTrue(script.contains("xsGetObjectCount"))
    }

    func testBuildNameAndStepAreEscaped() throws {
        let plan = build(
            id: "test-custom", name: "\"Test\"",
            steps: [BuildStep(action: "Use \"quoted\" command\non one line", targetVillagers: 3, targetTimeSeconds: 10)]
        )
        let script = try XSBuildExporter.generate(for: plan)
        XCTAssertTrue(script.contains("xsArraySetString(trainerBuildNames, 0, \"\\\"Test\\\"\")"))
        XCTAssertTrue(script.contains("Use \\\"quoted\\\" command on one line"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepTimes, 0, 10)"))
        XCTAssertEqual(XSBuildExporter.recommendedFileName(for: plan), "aoe2trainer_test-custom.xs")
    }

    func testXSUnicodeLabelsAreExplicitlyTransliteratedWithoutChangingJSONModel() throws {
        let plan = build(name: "Стрелки → Fast Castle — café", steps: [
            BuildStep(action: "Феодальная эпоха", targetTimeSeconds: 600,
                      unitGoals: [UnitGoal(objectId: 82, count: 1, label: "Замок")])
        ])
        let script = try XSBuildExporter.generate(for: plan)
        XCTAssertEqual(plan.name, "Стрелки → Fast Castle — café")
        XCTAssertEqual(plan.steps[0].action, "Феодальная эпоха")
        XCTAssertTrue(script.unicodeScalars.allSatisfy { $0.value < 128 })
        XCTAssertTrue(script.contains("-> Fast Castle - cafe"))
        XCTAssertTrue(script.contains("Feodal"))
        XCTAssertTrue(script.contains("Zamok"))
        XCTAssertTrue(script.contains("TEXT: ASCII transliteration (original in app/JSON)"))
        XCTAssertTrue(script.contains("trainerUsesASCIIText = true;"))
        let json = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(BuildOrder.self, from: json)
        XCTAssertEqual(decoded, plan)
    }

    func testUntransliterableSymbolsAreNotSilentlyDropped() throws {
        let plan = build(name: "Camel 🐫", steps: [
            BuildStep(action: "Keep control \u{001B} visible", targetTimeSeconds: 10)
        ])
        let script = try XSBuildExporter.generate(for: plan)
        XCTAssertTrue(script.unicodeScalars.allSatisfy { $0.value < 128 })
        XCTAssertTrue(script.contains("[U+1F42B]"))
        XCTAssertTrue(script.contains("[U+001B]"))
    }

    func testUnitWorkerAndTechnologyTargetsHaveContiguousRanges() throws {
        let plan = build(steps: [
            BuildStep(
                action: "Feudal checkpoint", targetVillagers: 20, targetTimeSeconds: 600,
                allocation: ResourceAllocation(food: 6, wood: 4, gold: 0, stone: 0),
                unitGoals: [UnitGoal(objectId: 101, count: 1, label: "Stable")],
                technologyGoals: [TechnologyGoal(technologyId: 101, label: "Feudal Age")]
            ),
            BuildStep(
                action: "Castle checkpoint", targetTimeSeconds: 960,
                unitGoals: [UnitGoal(objectId: 109, count: 2, label: "Town Centers")],
                technologyGoals: [TechnologyGoal(technologyId: 102, label: "Castle Age")]
            )
        ])
        let script = try XSBuildExporter.generate(for: plan)
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepTimes, 0, 600)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepFood, 0, 6)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepWood, 0, 4)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepUnitStarts, 1, 1)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepUnitCounts, 1, 1)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerUnitGoalObjects, 0, 101)"))
        XCTAssertTrue(script.contains("xsArraySetString(trainerUnitGoalLabels, 0, \"Stable\")"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerStepTechStarts, 1, 1)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerTechGoalIDs, 0, 101)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerTechGoalIDs, 1, 102)"))
        XCTAssertTrue(script.contains("xsGetTechState(xsArrayGetInt(trainerTechGoalIDs, techIndex), player) != 3"))
    }

    func testCivilizationSelectorsCompileToActualXSIDs() throws {
        let plan = build(civilizations: ["turks", "portuguese", "italians"], steps: [
            BuildStep(action: "Common opening", targetVillagers: 6, targetTimeSeconds: 75),
            BuildStep(action: "Research Chemistry", targetTimeSeconds: 1500,
                      exclude: ["turks"],
                      technologyGoals: [TechnologyGoal(technologyId: 47, label: "Chemistry")]),
            BuildStep(action: "Non-Turk option", targetTimeSeconds: 1600,
                      includeOnly: ["portuguese", "italians"])
        ])
        let script = try XSBuildExporter.generate(for: plan)
        XCTAssertTrue(script.contains("trainerAllowedPairCount = 3;"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerAllowedCivilizations, 0, 10)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerAllowedCivilizations, 1, 24)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerAllowedCivilizations, 2, 19)"))
        XCTAssertTrue(script.contains("trainerIncludedPairCount = 2;"))
        XCTAssertTrue(script.contains("xsArraySetBool(trainerStepUsesIncludeOnly, 2, true)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerIncludedSteps, 0, 2)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerIncludedCivilizations, 0, 24)"))
        XCTAssertTrue(script.contains("trainerExcludedPairCount = 1;"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerExcludedSteps, 0, 1)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerExcludedCivilizations, 0, 10)"))
    }

    func testSharedBuildDoesNotDuplicateAllStepsForEveryCivilization() throws {
        let steps = (0..<10).map {
            BuildStep(action: "Checkpoint \($0)", targetVillagers: $0 + 3, targetTimeSeconds: $0 * 30)
        }
        let plan = build(civilizations: CivilizationCatalog.standard.map(\.id), steps: steps)
        let script = try XSBuildExporter.generate(for: plan)
        XCTAssertTrue(script.contains("trainerStepCount = 10;"))
        XCTAssertEqual(script.components(separatedBy: "xsArraySetString(trainerStepLabels,").count - 1, 10)
        XCTAssertTrue(script.contains("trainerAllowedPairCount = \(CivilizationCatalog.standard.count);"))
    }

    func testPreferredBuildIsNotAnEligibilityOverride() throws {
        let portuguese = build(id: "portuguese", civilizations: ["portuguese"])
        let turks = build(id: "turks", civilizations: ["turks"])
        let script = try XSBuildExporter.generate(builds: [portuguese, turks], preferredBuildID: turks.id)
        XCTAssertTrue(script.contains("trainerPreferredBuild = 1;"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerAllowedBuilds, 0, 0)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerAllowedCivilizations, 0, 24)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerAllowedBuilds, 1, 1)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerAllowedCivilizations, 1, 10)"))
        // Selection is taken from the already filtered list, never the raw ID.
        XCTAssertTrue(script.contains("trainerSelectBuildSlot(requestedSlot);"))
        XCTAssertTrue(script.contains("trainerSelectedBuild = xsArrayGetInt(trainerEligibleBuilds, slot);"))
    }

    func testSwitchingReusesArraysAndKeepsAchievementHistory() throws {
        let script = try XSBuildExporter.generate(for: build())
        let selectionFunction = try XCTUnwrap(
            script.components(separatedBy: "void trainerSelectBuildSlot(int slot = 0) {").last?
                .components(separatedBy: "bool trainerRefreshContext()").first
        )
        XCTAssertFalse(selectionFunction.contains("xsArrayCreate"))
        XCTAssertFalse(selectionFunction.contains("xsArraySetInt(trainerStepDoneTimes"))
        XCTAssertTrue(script.contains("void trainerNextBuild()"))
        XCTAssertTrue(script.contains("void trainerPreviousBuild()"))
        XCTAssertTrue(script.contains("void trainerNextStep()"))
        XCTAssertTrue(script.contains("void trainerPreviousStep()"))
        XCTAssertTrue(script.contains("if (xsArrayGetBool(trainerStepEnabled, i) &&"))
    }

    func testStartingFoodRequirementsExportAsPositiveAndThresholds() throws {
        let generic = build(id: "generic", strategyFamily: "fast-castle")
        let hunt = build(id: "hunt", strategyFamily: "fast-castle",
                         startingFoodRequirements: [.init(kind: .pushableHunt, minCount: 3)])
        let mixed = build(id: "mixed", strategyFamily: "fast-castle",
                          startingFoodRequirements: [.init(kind: .pushableHunt, minCount: 2),
                                                     .init(kind: .smallGame, minCount: 4)])
        let script = try XSBuildExporter.generate(builds: [generic, hunt, mixed], preferredBuildID: hunt.id)
        XCTAssertTrue(script.contains("trainerBuildPushableMinimums = xsArrayCreateInt(3, 0,"))
        XCTAssertTrue(script.contains("trainerBuildSmallGameMinimums = xsArrayCreateInt(3, 0,"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerBuildPushableMinimums, 1, 3)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerBuildPushableMinimums, 2, 2)"))
        XCTAssertTrue(script.contains("xsArraySetInt(trainerBuildSmallGameMinimums, 2, 4)"))
        XCTAssertTrue(script.contains("xsArraySetString(trainerBuildFamilies, 1, \"fast-castle\")"))
        XCTAssertTrue(script.contains("trainerObservedPushableHuntCount >= xsArrayGetInt(trainerBuildPushableMinimums, buildIndex) &&"))
        XCTAssertTrue(script.contains("trainerObservedSmallGameCount >= xsArrayGetInt(trainerBuildSmallGameMinimums, buildIndex)"))
        XCTAssertFalse(script.contains("// @FOOD_OBSERVER@"))
    }

    func testFoodDiscoveryDoesNotReplaceActiveBuildAndGoalsRemainCivilizationEligible() throws {
        let script = try XSBuildExporter.generate(for: build())
        XCTAssertTrue(script.contains("bool enabled = xsArrayGetBool(trainerBuildCivEnabled, stepBuild) &&"))
        XCTAssertTrue(script.contains("if (selectedSlot >= 0) {\n        trainerSelectedBuildSlot = selectedSlot;\n        return;"))
        XCTAssertTrue(script.contains("trainerRequestedBuild = trainerSelectedBuild;"))
        XCTAssertTrue(script.contains("trainerPendingBuild = trainerRequestedBuild;"))
        XCTAssertTrue(script.contains("WAITING FOR STARTING-FOOD EVIDENCE"))
        XCTAssertTrue(script.contains("SAME-FAMILY FALLBACK"))
        XCTAssertTrue(script.contains("requestedFamily != \"\" &&"))
        XCTAssertTrue(script.contains("xsArrayGetString(trainerBuildFamilies, eligibleIndex) == requestedFamily"))
    }

    func testFoodObserverIsSelfContainedResettableAndRunsBeforeEligibilityRefresh() throws {
        let script = try XSBuildExporter.generate(for: build())
        XCTAssertTrue(script.contains("void trainerFoodInitialize()"))
        XCTAssertTrue(script.contains("trainerFoodInitialize();"))
        XCTAssertTrue(script.contains("trainerFoodReset();"))
        XCTAssertTrue(script.contains("trainerObserveStartingFood(player, now);\n    trainerRefreshEligibleBuilds();"))
        XCTAssertTrue(script.contains("bool rewound = trainerLastContextTime >= 0 && now < trainerLastContextTime;"))
        XCTAssertTrue(script.contains("START FOOD SEEN:"))
        XCTAssertTrue(script.contains("not remaining; 0=unknown"))
        XCTAssertTrue(script.contains("INCOMPLETE lower bounds"))
    }

    func testFoodObserverChecksVisibilityBeforeReadingAnimalData() throws {
        let script = try XSBuildExporter.generate(for: build())
        let observer = try XCTUnwrap(
            script.components(separatedBy: "void trainerFoodObserveSpecies(").last?
                .components(separatedBy: "void trainerObserveStartingFood(").first
        )
        let visibility = try XCTUnwrap(observer.range(of: "if (xsUnsyncIsUnitVisible(animal, false, player))"))
        for read in ["xsGetUnitObjectId(animal)", "xsGetUnitHitpoints(animal)",
                     "xsGetUnitPosition(animal)"] {
            let dataRead = try XCTUnwrap(observer.range(of: read))
            XCTAssertLessThan(visibility.lowerBound, dataRead.lowerBound)
        }
        XCTAssertFalse(observer.contains("xsUnsyncIsUnitVisible(animal, true"))
        XCTAssertFalse(observer.contains("xsVectorGetZ"))
        XCTAssertTrue(observer.contains("xsVectorGetX(position)"))
        XCTAssertTrue(observer.contains("xsVectorGetY(position)"))
        XCTAssertTrue(observer.contains("xsGetUnitHitpoints(animal) > 0.0"))
        XCTAssertTrue(observer.contains("dx * dx + dy * dy <= trainerFoodRadiusSquared"))
    }

    func testFoodObserverWhitelistsSpeciesAndNeverCountsHerdableChickensOrGoldFoxes() throws {
        let script = try XSBuildExporter.generate(for: build())
        let initialization = try XCTUnwrap(
            script.components(separatedBy: "void trainerFoodInitialize()").last?
                .components(separatedBy: "int trainerFoodCategory(").first
        )
        let species = [65, 1019, 1026, 1239, 1796, 1896,
                       2084, 2086, 2088, 2098, 2099, 2100, 2739]
        XCTAssertTrue(script.contains("const int trainerFoodSpeciesCount = \(species.count);"))
        for (slot, objectID) in species.enumerated() {
            XCTAssertTrue(initialization.contains("xsArraySetInt(trainerFoodSpeciesIDs, \(slot), \(objectID));"))
        }
        let classification = try XCTUnwrap(
            script.components(separatedBy: "int trainerFoodCategory(").last?
                .components(separatedBy: "bool trainerFoodWasObserved(").first
        )
        for objectID in [43, 2083, 2085, 2087, 1955, 1958, 2591, 2597, 2735] {
            XCTAssertFalse(classification.contains("objectID == \(objectID)"))
        }
        XCTAssertTrue(script.contains("xsGetPlayerUnitIds(0, objectID, trainerFoodCandidateIDs)"))
        XCTAssertFalse(script.contains("xsGetPlayerUnitIds(0, cPreyAnimalClass"))
    }

    func testFoodObserverDeduplicatesInstancesBeforeCheckingCapacity() throws {
        let script = try XSBuildExporter.generate(for: build())
        let remembering = try XCTUnwrap(
            script.components(separatedBy: "void trainerFoodRemember(").last?
                .components(separatedBy: "void trainerFoodFindAnchor(").first
        )
        let deduplication = try XCTUnwrap(remembering.range(of: "if (trainerFoodWasObserved(unitID))"))
        let capacity = try XCTUnwrap(remembering.range(of: "if (trainerFoodSeenCount >= trainerFoodSeenCapacity)"))
        XCTAssertLessThan(deduplication.lowerBound, capacity.lowerBound)
        XCTAssertTrue(remembering.contains("unitID < 0"))
        XCTAssertTrue(remembering.contains("xsArraySetInt(trainerFoodSeenUnitIDs, trainerFoodSeenCount, unitID) == false"))
        XCTAssertFalse(remembering.contains("xsArrayCreate"))
        XCTAssertTrue(script.contains("xsArrayGetInt(trainerFoodSeenUnitIDs, seenIndex) == unitID"))
    }

    func testFoodObservationsAreOpeningLowerBoundsWithExplicitUnknownStates() throws {
        let script = try XSBuildExporter.generate(for: build())
        XCTAssertTrue(script.contains("const int trainerFoodSeenCapacity = 512;"))
        XCTAssertTrue(script.contains("const int trainerFoodCandidatesPerSpecies = 256;"))
        XCTAssertTrue(script.contains("const int trainerFoodOpeningSeconds = 600;"))
        XCTAssertTrue(script.contains("const float trainerFoodRadiusSquared = 576.0;"))
        XCTAssertTrue(script.contains("(start + checks) % count"))
        XCTAssertTrue(script.contains("if (trainerFoodHasAnchor) {\n        return;"))
        XCTAssertTrue(script.contains("if (now > trainerFoodOpeningSeconds)"))
        XCTAssertTrue(script.contains("NO FOOD VARIANT CONFIRMED: observations below requirements"))
        XCTAssertTrue(script.contains("if (trainerCivCompatibleBuildCount == 0)"))
    }

    func testDeadlinesAreShownBeforeTheyExpireAndManualActionsAreNotCompleted() throws {
        let script = try XSBuildExporter.generate(for: build())
        XCTAssertTrue(script.contains("if (deadline < 0 || now <= deadline)"))
        XCTAssertTrue(script.contains("return (\"MANUAL ACTION\");"))
        XCTAssertTrue(script.contains("trainerGoalIsMet(i, player, villagers"))
        XCTAssertTrue(script.contains("trainerManualStepSlot = next;"))
    }

    func testUnknownEmptyAndDuplicateCatalogsAreRejected() throws {
        XCTAssertThrowsError(try XSBuildExporter.generate(builds: []))
        let plan = build()
        XCTAssertThrowsError(try XSBuildExporter.generate(builds: [plan, plan]))
        XCTAssertThrowsError(try XSBuildExporter.generate(for: build(civilizations: ["unknown-civ"])))
        XCTAssertThrowsError(try XSBuildExporter.generate(for: build(steps: [
            BuildStep(action: "Wrong civilization", includeOnly: ["franks"])
        ])))
    }

    func testOversizedCatalogIsRejected() {
        let plans = (0..<129).map { build(id: "build-\($0)") }
        XCTAssertThrowsError(try XSBuildExporter.generate(builds: plans)) { error in
            guard let exportError = error as? XSBuildExporter.ExportError,
                  case .catalogTooLarge = exportError else {
                return XCTFail("Expected catalogTooLarge, got \(error)")
            }
        }
    }

    func testWorkerQueryUsesPlayerFirstAndReusesArray() throws {
        let script = try XSBuildExporter.generate(for: build())
        XCTAssertTrue(script.contains("xsGetPlayerUnitIds(player, cVillagerClass, trainerVillagerIDs)"))
        XCTAssertFalse(script.contains("xsGetPlayerUnitIds(cVillagerClass, player"))
        XCTAssertTrue(script.contains("if (unitClass >= 0 && unitClass <= 64)"))
        XCTAssertTrue(script.contains("unitClass = unitClass + 900;"))
        XCTAssertTrue(script.contains("xsGetUnitAttributeHeld(villager, cAttributeMeat)"))
        XCTAssertTrue(script.contains("APPROXIMATE"))
    }

    func testWorkerClassificationChecksVisibilityAndTreatsGoldFoxesAsGold() throws {
        let script = try XSBuildExporter.generate(for: build())
        let classifier = try XCTUnwrap(
            script.components(separatedBy: "void trainerCountWorkers(").last?
                .components(separatedBy: "int trainerHistoryIndex(").first
        )
        let visibility = try XCTUnwrap(classifier.range(of: "if (xsUnsyncIsUnitVisible(target, false, player))"))
        for read in ["xsGetUnitObjectId(target)", "xsGetUnitClass(target)"] {
            XCTAssertLessThan(visibility.lowerBound, try XCTUnwrap(classifier.range(of: read)).lowerBound)
        }
        let fox = try XCTUnwrap(classifier.range(of: "if (targetObject == 1955 || targetObject == 1958)"))
        let prey = try XCTUnwrap(classifier.range(of: "unitClass == cPreyAnimalClass"))
        XCTAssertLessThan(fox.lowerBound, prey.lowerBound)
        XCTAssertTrue(classifier.contains("if (targetObject == 1955 || targetObject == 1958) {\n            gold = gold + 1;"))
        XCTAssertTrue(classifier.contains("if (targetObject == 43) {\n                    unitClass = -1;"))
        XCTAssertTrue(classifier.contains("xsGetUnitAttributeHeld(villager, cAttributeGold) > 0"))
    }

    func testTemplateUsesDocumentedXSGrammarRatherThanCStyle() throws {
        let script = try XSBuildExporter.generate(for: build())
        XCTAssertFalse(script.contains("for (int "))
        XCTAssertFalse(script.contains("if (!"))
        XCTAssertFalse(script.contains("infiniteLoopLimit 100000"))
        XCTAssertTrue(script.contains("for (i = 0; < trainerStepCount)"))
        XCTAssertTrue(script.contains("infiniteLoopLimit = 100000;"))
        XCTAssertTrue(script.contains("return (false);"))
        XCTAssertTrue(script.contains("void trainerSelectBuildSlot(int slot = 0)"))
        XCTAssertFalse(script.contains("string label ="))
        XCTAssertTrue(script.contains("string trainerRateLine(string resourceName ="))
    }

    func testRollingWindowKeepsFractionalTimeWeightedWorkerCounts() throws {
        let script = try XSBuildExporter.generate(for: build())
        XCTAssertTrue(script.contains("float trainerAverageWorkers("))
        XCTAssertTrue(script.contains("float workerSeconds = 0.0;"))
        XCTAssertTrue(script.contains("xsArrayGetInt(arrayID, before) * (end - start)"))
        XCTAssertTrue(script.contains("return (workerSeconds / trainerWindowSeconds);"))
        XCTAssertTrue(script.contains("trainerOneDecimal(rate / workers)"))
        XCTAssertFalse(script.contains("return (sum / sampleCount);"))
    }

    func testRollingWindowInterpolatesExactBoundaryAndRejectsGapsAndResets() throws {
        let script = try XSBuildExporter.generate(for: build())
        XCTAssertTrue(script.contains("trainerWindowFraction = 1.0 * (cutoff - beforeTime) / gap;"))
        XCTAssertTrue(script.contains("float baseline = before + (after - before) * trainerWindowFraction;"))
        XCTAssertTrue(script.contains("gap > trainerMaxSampleGap"))
        XCTAssertTrue(script.contains("DATA GAP"))
        XCTAssertTrue(script.contains("COUNTER/TIME RESET"))
        XCTAssertTrue(script.contains("WARMUP"))
        XCTAssertTrue(script.contains("ECONOMY DATA UNAVAILABLE"))
        XCTAssertTrue(script.contains("xsArrayCreateFloat(trainerHistorySize, 0.0"))
        XCTAssertTrue(script.contains("foodTotal < xsArrayGetFloat(trainerTotalsFood, previousIndex)"))
        XCTAssertFalse(script.contains("gained * 60 / elapsed"))
    }

    /// CI compiles Swift and exports the exact bundled catalog for a separate
    /// XS syntax/API check. This is not an in-game compatibility test.
    func testExportBundledCatalogForOptionalXSCheck() throws {
        guard let output = ProcessInfo.processInfo.environment["AOE2_TRAINER_XS_OUTPUT"] else { return }
        let script = try XSBuildExporter.generate(builds: BuildOrderLibrary.bundled())
        let url = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(script.contains("// @CATALOG_SETUP@"))
        XCTAssertTrue(script.unicodeScalars.allSatisfy { $0.value < 128 })
    }
}
