import Foundation
import XCTest
@testable import AoE2MacTrainer

final class BuildOrderSchemaTests: XCTestCase {
    private func makeBuild(id: String = "fast-imperial", civilizations: [String] = ["turks", "portuguese"],
                           steps: [BuildStep] = [BuildStep(action: "Start", targetTimeSeconds: 0)],
                           strategyFamily: String? = nil,
                           startingFoodRequirements: [StartingFoodRequirement]? = nil) -> BuildOrder {
        BuildOrder(id: id, name: "Fast Imperial — gunpowder",
                   civilizations: civilizations, map: "Арена", strategy: "Fast Imperial",
                   description: "Test fixture, not a benchmark", steps: steps,
                   sources: [BuildSource(title: "Example source", url: "https://example.com/build")],
                   planStatus: "practice-targets", strategyFamily: strategyFamily,
                   startingFoodRequirements: startingFoodRequirements)
    }

    private func declarations(_ ids: [String] = ["turks", "portuguese"]) throws -> [CivilizationDefinition] {
        try ids.map { try XCTUnwrap(CivilizationCatalog.resolve($0)) }
    }

    private func documentData(builds: [BuildOrder]? = nil,
                              civilizations: [CivilizationDefinition]? = nil,
                              version: Int = 2) throws -> Data {
        let document = BuildOrderDocument(schemaVersion: version,
                                          civilizations: try civilizations ?? declarations(),
                                          builds: builds ?? [makeBuild()])
        return try JSONEncoder().encode(document)
    }

    private func mutatedDocument(_ change: (inout [String: Any]) throws -> Void) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: documentData())
        var dictionary = try XCTUnwrap(object as? [String: Any])
        try change(&dictionary)
        return try JSONSerialization.data(withJSONObject: dictionary)
    }

    private func documentWithFoodRequirements(_ value: Any) throws -> Data {
        try mutatedDocument { dictionary in
            var builds = try XCTUnwrap(dictionary["builds"] as? [[String: Any]])
            builds[0]["startingFoodRequirements"] = value
            dictionary["builds"] = builds
        }
    }

    private func assertUnknownKey(_ data: Data, key: String, path: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try BuildOrderLibrary.decode(data), file: file, line: line) { error in
            XCTAssertTrue(error.localizedDescription.contains("неизвестное поле"), file: file, line: line)
            XCTAssertTrue(error.localizedDescription.contains(key), file: file, line: line)
            XCTAssertTrue(error.localizedDescription.contains(path), file: file, line: line)
        }
    }

    private func makeTempDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AoE2BuildSchema-Tests-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testNewCustomFileUsesV2AndEmptyOverridesPreserveBase() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom/builds.json")
        _ = try BuildOrderLibrary.prepareCustomBuildsFile(at: url)
        let document = try JSONDecoder().decode(BuildOrderDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.civilizations, CivilizationCatalog.standard)
        XCTAssertTrue(document.builds.isEmpty)
        XCTAssertEqual(try BuildOrderLibrary.loadAll(customURL: url, bundled: [makeBuild()]), [makeBuild()])

        try Data("[]".utf8).write(to: url, options: .atomic)
        XCTAssertEqual(try BuildOrderLibrary.loadAll(customURL: url, bundled: [makeBuild()]), [makeBuild()])
    }

    func testPreparingCustomFileNeverOverwritesExistingEdits() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("builds.json")
        let original = try documentData()
        try original.write(to: url)
        _ = try BuildOrderLibrary.prepareCustomBuildsFile(at: url)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testInvalidCustomDocumentThrowsInsteadOfReturningBundledFallback() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("builds.json")
        let invalid = try documentData(civilizations: declarations(["turks"]))
        try invalid.write(to: url)
        XCTAssertThrowsError(try BuildOrderLibrary.loadAll(customURL: url, bundled: [makeBuild()]))
    }

    func testV2DocumentUsesExplicitCivilizationDeclarations() throws {
        let decoded = try BuildOrderLibrary.decodeDocument(documentData())
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.civilizations.map(\.id), ["turks", "portuguese"])
        XCTAssertEqual(decoded.builds[0].civilizations, ["turks", "portuguese"])
        XCTAssertEqual(decoded.builds[0].sources, makeBuild().sources)
        XCTAssertEqual(decoded.builds[0].planStatus, "practice-targets")
    }

    func testBuildCannotUseKnownButUndeclaredCivilization() throws {
        let data = try documentData(civilizations: declarations(["turks"]))
        XCTAssertThrowsError(try BuildOrderLibrary.decode(data)) { error in
            XCTAssertTrue(error.localizedDescription.contains("portuguese"))
            XCTAssertTrue(error.localizedDescription.contains("не объявлена"))
        }
    }

    func testUnknownDeclarationAndIncorrectEngineIDAreRejected() throws {
        let unknown = CivilizationDefinition(id: "imaginary", name: "Imaginary", xsID: 999)
        XCTAssertThrowsError(try BuildOrderLibrary.decode(documentData(civilizations: [unknown])))

        let turks = try XCTUnwrap(CivilizationCatalog.resolve("turks"))
        let wrongID = CivilizationDefinition(id: turks.id, name: turks.name, xsID: turks.xsID + 1000)
        XCTAssertThrowsError(try BuildOrderLibrary.decode(documentData(civilizations: [wrongID]))) { error in
            XCTAssertTrue(error.localizedDescription.contains("xsID"))
        }
    }

    func testDuplicateDeclarationIDsAndEngineIDsAreRejected() throws {
        let turks = try XCTUnwrap(CivilizationCatalog.resolve("turks"))
        let portuguese = try XCTUnwrap(CivilizationCatalog.resolve("portuguese"))
        XCTAssertThrowsError(try BuildOrderLibrary.decode(documentData(civilizations: [turks, turks])))
        let duplicateEngine = CivilizationDefinition(id: portuguese.id, name: portuguese.name, xsID: turks.xsID)
        XCTAssertThrowsError(try BuildOrderLibrary.decode(documentData(civilizations: [turks, duplicateEngine])))
    }

    func testV2RequiresCanonicalIDsAndDoesNotAcceptLegacyAny() throws {
        let data = try mutatedDocument { dictionary in
            var builds = try XCTUnwrap(dictionary["builds"] as? [[String: Any]])
            builds[0]["civilizations"] = ["Любая"]
            dictionary["builds"] = builds
        }
        XCTAssertThrowsError(try BuildOrderLibrary.decode(data))
    }

    func testV2RequiresPluralArrayNotLegacySingularString() throws {
        let data = try mutatedDocument { dictionary in
            var builds = try XCTUnwrap(dictionary["builds"] as? [[String: Any]])
            builds[0].removeValue(forKey: "civilizations")
            builds[0]["civilization"] = "Турки"
            dictionary["builds"] = builds
        }
        XCTAssertThrowsError(try BuildOrderLibrary.decode(data))
    }

    func testStepSelectorsMustBeArrays() throws {
        let invalidValues: [Any] = ["turks", NSNull()]
        for selector in ["includeOnly", "exclude"] {
            for invalid in invalidValues {
                let data = try mutatedDocument { dictionary in
                    var builds = try XCTUnwrap(dictionary["builds"] as? [[String: Any]])
                    var steps = try XCTUnwrap(builds[0]["steps"] as? [[String: Any]])
                    steps[0][selector] = invalid
                    builds[0]["steps"] = steps
                    dictionary["builds"] = builds
                }
                XCTAssertThrowsError(try BuildOrderLibrary.decode(data)) { error in
                    XCTAssertTrue(error.localizedDescription.contains(selector))
                    XCTAssertTrue(error.localizedDescription.contains("массивом"))
                }
            }
        }
    }

    func testV2RejectsMisspelledSelectorsInsteadOfSilentlyEnablingAllCivilizations() throws {
        for key in ["includes", "include_only", "exlclude"] {
            let data = try mutatedDocument { dictionary in
                var builds = try XCTUnwrap(dictionary["builds"] as? [[String: Any]])
                var steps = try XCTUnwrap(builds[0]["steps"] as? [[String: Any]])
                steps[0][key] = ["turks"]
                builds[0]["steps"] = steps
                dictionary["builds"] = builds
            }
            assertUnknownKey(data, key: key, path: "$.builds[0].steps[0]")
            XCTAssertThrowsError(try BuildOrderLibrary.decode(data)) { error in
                XCTAssertTrue(error.localizedDescription.contains("fast-imperial"))
                XCTAssertTrue(error.localizedDescription.contains("includeOnly"))
                XCTAssertTrue(error.localizedDescription.contains("exclude"))
            }
        }
    }

    func testV2RejectsUnknownRootBuildDeclarationAndSourceKeys() throws {
        let root = try mutatedDocument { $0["defaultCivilization"] = "turks" }
        assertUnknownKey(root, key: "defaultCivilization", path: "$")

        let declaration = try mutatedDocument { dictionary in
            var civilizations = try XCTUnwrap(dictionary["civilizations"] as? [[String: Any]])
            civilizations[0]["xsId"] = 10
            dictionary["civilizations"] = civilizations
        }
        assertUnknownKey(declaration, key: "xsId", path: "$.civilizations[0]")

        let build = try mutatedDocument { dictionary in
            var builds = try XCTUnwrap(dictionary["builds"] as? [[String: Any]])
            builds[0]["exclude"] = ["turks"]
            dictionary["builds"] = builds
        }
        assertUnknownKey(build, key: "exclude", path: "$.builds[0]")

        let source = try mutatedDocument { dictionary in
            var builds = try XCTUnwrap(dictionary["builds"] as? [[String: Any]])
            var sources = try XCTUnwrap(builds[0]["sources"] as? [[String: Any]])
            sources[0]["link"] = "https://example.com/build"
            builds[0]["sources"] = sources
            dictionary["builds"] = builds
        }
        assertUnknownKey(source, key: "link", path: "$.builds[0].sources[0]")
    }

    func testV2RejectsUnknownNestedAllocationAndGoalKeys() throws {
        let cases: [(field: String, badKey: String, value: Any, pathSuffix: String)] = [
            ("allocation", "foodWorkers",
             ["food": 6, "wood": 0, "gold": 0, "stone": 0, "foodWorkers": 6] as [String: Any], "allocation"),
            ("unitGoals", "objectID",
             [["objectId": 74, "count": 1, "label": "Militia", "objectID": 74]] as [[String: Any]], "unitGoals[0]"),
            ("technologyGoals", "technologyID",
             [["technologyId": 101, "label": "Feudal", "technologyID": 101]] as [[String: Any]], "technologyGoals[0]")
        ]
        for testCase in cases {
            let data = try mutatedDocument { dictionary in
                var builds = try XCTUnwrap(dictionary["builds"] as? [[String: Any]])
                var steps = try XCTUnwrap(builds[0]["steps"] as? [[String: Any]])
                steps[0][testCase.field] = testCase.value
                builds[0]["steps"] = steps
                dictionary["builds"] = builds
            }
            assertUnknownKey(data, key: testCase.badKey,
                             path: "$.builds[0].steps[0].\(testCase.pathSuffix)")
        }
    }

    func testLegacyArrayImportRemainsPermissiveAboutUnknownKeys() throws {
        let initial = try JSONSerialization.jsonObject(with: JSONEncoder().encode([makeBuild()]))
        var builds = try XCTUnwrap(initial as? [[String: Any]])
        builds[0]["oldEditorMetadata"] = "preserved by external tool"
        var steps = try XCTUnwrap(builds[0]["steps"] as? [[String: Any]])
        steps[0]["oldNote"] = "legacy optional field"
        builds[0]["steps"] = steps
        let data = try JSONSerialization.data(withJSONObject: builds)
        XCTAssertEqual(try BuildOrderLibrary.decode(data), [makeBuild()])
    }

    func testFoodMetadataRoundTripsAndSurvivesCivilizationResolution() throws {
        let requirements = [StartingFoodRequirement(kind: .pushableHunt, minCount: 3)]
        let build = makeBuild(strategyFamily: "fast-castle", startingFoodRequirements: requirements)
        let decoded = try XCTUnwrap(BuildOrderLibrary.decode(documentData(builds: [build])).first)
        XCTAssertEqual(decoded, build)
        let resolved = try XCTUnwrap(decoded.resolved(for: "turks"))
        XCTAssertEqual(resolved.strategyFamily, "fast-castle")
        XCTAssertEqual(resolved.startingFoodRequirements, requirements)
        XCTAssertEqual(resolved.civilizations, ["turks"])
        XCTAssertTrue(decoded.supports(civilizationID: "turks"), "supports remains civilization-only")
        XCTAssertTrue(BuildOrderLibrary.eligible([resolved], civilizationID: "turks").isEmpty,
                      "Resolving a civilization must not erase food restrictions")
    }

    func testLegacyNormalizationPreservesFoodConditionsAndFamily() throws {
        let requirements = [StartingFoodRequirement(kind: .smallGame, minCount: 2)]
        let original = BuildOrder(id: "legacy-food", name: "Legacy", civilization: "Турки, Португальцы",
                                  map: "Арена", strategy: "Fast Castle", description: "",
                                  steps: [BuildStep(action: "Start")], strategyFamily: "fast-castle",
                                  startingFoodRequirements: requirements)
        let decoded = try XCTUnwrap(BuildOrderLibrary.decode(JSONEncoder().encode([original])).first)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.startingFoodRequirements, requirements)
        XCTAssertTrue(BuildOrderLibrary.eligible([decoded], civilizationID: "turks").isEmpty)
    }

    func testFoodEligibilityKeepsGenericFallbackAndStillRequiresMatchingCivilization() throws {
        let hunt: [StartingFoodRequirement] = [.init(kind: .pushableHunt, minCount: 3)]
        let small: [StartingFoodRequirement] = [.init(kind: .smallGame, minCount: 2)]
        let builds = [
            makeBuild(id: "generic", strategyFamily: "fast-castle"),
            makeBuild(id: "generic-empty", strategyFamily: "fast-castle", startingFoodRequirements: []),
            makeBuild(id: "hunt", strategyFamily: "fast-castle", startingFoodRequirements: hunt),
            makeBuild(id: "small", strategyFamily: "fast-castle", startingFoodRequirements: small),
            makeBuild(id: "foreign-hunt", civilizations: ["franks"], strategyFamily: "fast-castle",
                      startingFoodRequirements: hunt)
        ]
        try BuildOrderLibrary.validate(builds)
        XCTAssertEqual(BuildOrderLibrary.eligible(builds, civilizationID: "turks").map(\.id),
                       ["generic", "generic-empty"])
        XCTAssertEqual(BuildOrderLibrary.eligible(builds, civilizationID: "turks",
                                                  startingFoodEvidence: .init(pushableHuntCount: 2)).map(\.id),
                       ["generic", "generic-empty"])
        XCTAssertEqual(BuildOrderLibrary.eligible(builds, civilizationID: "turks",
                                                  startingFoodEvidence: .init(pushableHuntCount: 3)).map(\.id),
                       ["generic", "generic-empty", "hunt"])
        XCTAssertEqual(BuildOrderLibrary.eligible(builds, civilizationID: "turks",
                                                  startingFoodEvidence: .init(smallGameCount: 2)).map(\.id),
                       ["generic", "generic-empty", "small"])
        let both = StartingFoodEvidence(pushableHuntCount: 3, smallGameCount: 2)
        XCTAssertEqual(BuildOrderLibrary.eligible(builds, civilizationID: "turks",
                                                  startingFoodEvidence: both).map(\.id),
                       ["generic", "generic-empty", "hunt", "small"])
        XCTAssertTrue(BuildOrderLibrary.eligible(builds, civilizationID: nil, startingFoodEvidence: both).isEmpty)
        XCTAssertTrue(BuildOrderLibrary.eligible(builds, civilizationID: "unknown", startingFoodEvidence: both).isEmpty)
    }

    func testStrategyFamilyMustBeNonemptyKebabID() throws {
        for invalid in ["", " ", "Fast-Castle", "fast_castle", "-fast", "fast-", "fast--castle", "быстрый-замок"] {
            XCTAssertThrowsError(try BuildOrderLibrary.validate([makeBuild(strategyFamily: invalid)])) { error in
                XCTAssertTrue(error.localizedDescription.contains("strategyFamily"))
            }
        }
        for valid in ["fast-castle", "fast-imperial", "fc", "phase-2"] {
            XCTAssertNoThrow(try BuildOrderLibrary.validate([makeBuild(strategyFamily: valid)]))
        }
    }

    func testFoodRequirementCountLimitsAndUniqueKinds() throws {
        for count in [-1, 0, 33] {
            XCTAssertThrowsError(try BuildOrderLibrary.validate([
                makeBuild(startingFoodRequirements: [.init(kind: .pushableHunt, minCount: count)])
            ])) { error in
                XCTAssertTrue(error.localizedDescription.contains("startingFoodRequirements.minCount"))
            }
        }
        XCTAssertThrowsError(try BuildOrderLibrary.validate([
            makeBuild(startingFoodRequirements: [
                .init(kind: .pushableHunt, minCount: 1), .init(kind: .pushableHunt, minCount: 3)
            ])
        ]))
        XCTAssertNoThrow(try BuildOrderLibrary.validate([
            makeBuild(startingFoodRequirements: [
                .init(kind: .pushableHunt, minCount: 1), .init(kind: .smallGame, minCount: 32)
            ])
        ]))
    }

    func testUnknownFoodKindsAndNonnumericIntegerCountsAreRejected() throws {
        for kind in ["deer", "Pushable-Hunt", "small_game", ""] {
            let data = try documentWithFoodRequirements([["kind": kind, "minCount": 3] as [String: Any]])
            XCTAssertThrowsError(try BuildOrderLibrary.decode(data))
        }
        let invalidCounts: [Any] = ["3", 1.5, true]
        for count in invalidCounts {
            let data = try documentWithFoodRequirements([["kind": "pushable-hunt", "minCount": count]])
            XCTAssertThrowsError(try BuildOrderLibrary.decode(data))
        }
        XCTAssertThrowsError(try BuildOrderLibrary.decode(documentWithFoodRequirements([["kind": "small-game"]])))
        XCTAssertThrowsError(try BuildOrderLibrary.decode(documentWithFoodRequirements("pushable-hunt")))
    }

    func testV2NullFoodAndFamilyFieldsAreNotSilentlyTreatedAsOmitted() throws {
        XCTAssertThrowsError(try BuildOrderLibrary.decode(documentWithFoodRequirements(NSNull()))) { error in
            XCTAssertTrue(error.localizedDescription.contains("startingFoodRequirements"))
            XCTAssertTrue(error.localizedDescription.contains("массивом"))
        }
        let invalidValues: [Any] = [NSNull(), 123, ["fast-castle"]]
        for invalid in invalidValues {
            let data = try mutatedDocument { dictionary in
                var builds = try XCTUnwrap(dictionary["builds"] as? [[String: Any]])
                builds[0]["strategyFamily"] = invalid
                dictionary["builds"] = builds
            }
            XCTAssertThrowsError(try BuildOrderLibrary.decode(data)) { error in
                XCTAssertTrue(error.localizedDescription.contains("strategyFamily"))
            }
        }
        XCTAssertNoThrow(try BuildOrderLibrary.decode(documentData()), "Omitted optional fields remain valid")
        XCTAssertNoThrow(try BuildOrderLibrary.decode(documentWithFoodRequirements([Any]())),
                         "An explicit empty array remains a generic plan")
    }

    func testUnknownFoodSelectorKeysAreRejectedAndCivSelectorsRemainCivOnly() throws {
        let data = try documentWithFoodRequirements([
            ["kind": "pushable-hunt", "minCount": 3, "exclude": ["small-game"]] as [String: Any]
        ])
        assertUnknownKey(data, key: "exclude", path: "$.builds[0].startingFoodRequirements[0]")
        let typo = try mutatedDocument { dictionary in
            var builds = try XCTUnwrap(dictionary["builds"] as? [[String: Any]])
            builds[0]["foodRequirements"] = [["kind": "pushable-hunt", "minCount": 3] as [String: Any]]
            dictionary["builds"] = builds
        }
        assertUnknownKey(typo, key: "foodRequirements", path: "$.builds[0]")
        XCTAssertThrowsError(try BuildOrderLibrary.validate([
            makeBuild(steps: [BuildStep(action: "Wrong selector type", includeOnly: ["small-game"])])
        ]))
    }

    func testStepCannotReferenceCivilizationOutsideBuildAllowlist() throws {
        let build = makeBuild(civilizations: ["portuguese"], steps: [
            BuildStep(action: "Research Chemistry", exclude: ["turks"])
        ])
        XCTAssertThrowsError(try BuildOrderLibrary.decode(documentData(builds: [build]))) { error in
            XCTAssertTrue(error.localizedDescription.contains("turks"))
            XCTAssertTrue(error.localizedDescription.contains("этого билда"))
        }
    }

    func testUnknownSelectorNamesRemainVisibleInError() throws {
        let build = makeBuild(steps: [BuildStep(action: "Start", includeOnly: ["not-a-civilization"])])
        XCTAssertThrowsError(try BuildOrderLibrary.validate([build])) { error in
            XCTAssertTrue(error.localizedDescription.contains("not-a-civilization"))
            XCTAssertTrue(error.localizedDescription.contains("includeOnly"))
        }
    }

    func testEmptyIncludeAndDuplicateReferencesAreRejected() throws {
        let empty = makeBuild(steps: [BuildStep(action: "Start", includeOnly: [])])
        XCTAssertThrowsError(try BuildOrderLibrary.validate([empty]))

        let duplicate = makeBuild(steps: [BuildStep(action: "Start", exclude: ["turks", "Турки"])])
        XCTAssertThrowsError(try BuildOrderLibrary.validate([duplicate]))

        let duplicateBuild = makeBuild(civilizations: ["Turks", "turks"])
        XCTAssertThrowsError(try BuildOrderLibrary.validate([duplicateBuild]))
    }

    func testEveryEligibleCivilizationNeedsAtLeastOneEffectiveStep() throws {
        let build = makeBuild(steps: [BuildStep(action: "Turks only", includeOnly: ["turks"])])
        XCTAssertThrowsError(try BuildOrderLibrary.validate([build])) { error in
            XCTAssertTrue(error.localizedDescription.contains("portuguese"))
            XCTAssertTrue(error.localizedDescription.contains("не осталось шагов"))
        }
    }

    func testResolveFiltersChemistryAndKeepsSourceMetadata() throws {
        let build = makeBuild(steps: [
            BuildStep(action: "Prepare economy", targetTimeSeconds: 0),
            BuildStep(action: "Research Chemistry", targetTimeSeconds: 1200, exclude: ["turks"],
                      technologyGoals: [TechnologyGoal(technologyId: 47, label: "Chemistry")]),
            BuildStep(action: "Chemistry is automatic", targetTimeSeconds: 1200, includeOnly: ["turks"],
                      technologyGoals: [TechnologyGoal(technologyId: 47, label: "Chemistry")])
        ])
        try BuildOrderLibrary.validate([build])
        let turks = try XCTUnwrap(build.resolved(for: "turks"))
        let portuguese = try XCTUnwrap(build.resolved(for: "portuguese"))

        XCTAssertEqual(turks.steps.map(\.action), ["Prepare economy", "Chemistry is automatic"])
        XCTAssertEqual(portuguese.steps.map(\.action), ["Prepare economy", "Research Chemistry"])
        XCTAssertEqual(turks.civilizations, ["turks"])
        XCTAssertEqual(turks.id, build.id)
        XCTAssertEqual(turks.name, build.name)
        XCTAssertEqual(turks.sources, build.sources)
        XCTAssertEqual(turks.planStatus, build.planStatus)
        XCTAssertTrue(turks.steps.allSatisfy { $0.includeOnly == nil && $0.exclude == nil })
        XCTAssertEqual(turks.steps.last?.technologyGoals?.first?.technologyId, 47)
        XCTAssertTrue(turks.hasValidGoalsAndTimeline)
        XCTAssertNil(turks.resolved(for: "portuguese"))
        XCTAssertEqual(build.steps.count, 3, "The original catalog must remain reusable.")
    }

    func testConditionalTimelinesAreValidatedPerCivilization() throws {
        let build = makeBuild(steps: [
            BuildStep(action: "Shared start", targetTimeSeconds: 100),
            BuildStep(action: "Portuguese variant", targetTimeSeconds: 200, includeOnly: ["portuguese"]),
            BuildStep(action: "Turkish variant", targetTimeSeconds: 150, includeOnly: ["turks"]),
            BuildStep(action: "Shared finish", targetTimeSeconds: 300)
        ])
        XCTAssertNoThrow(try BuildOrderLibrary.validate([build]))
        XCTAssertEqual(build.resolved(for: "turks")?.steps.compactMap(\.targetTimeSeconds), [100, 150, 300])

        let unordered = makeBuild(steps: [
            BuildStep(action: "Shared later", targetTimeSeconds: 200),
            BuildStep(action: "Turkish earlier", targetTimeSeconds: 150, includeOnly: ["turks"])
        ])
        XCTAssertThrowsError(try BuildOrderLibrary.validate([unordered]))
    }

    func testIncludeOnlyAndExcludeUseIntersectionSemantics() {
        let step = BuildStep(action: "Subset", includeOnly: ["turks", "portuguese"], exclude: ["turks"])
        XCTAssertTrue(step.applies(to: "portuguese"))
        XCTAssertFalse(step.applies(to: "turks"))
        XCTAssertFalse(step.applies(to: "spanish"))
        XCTAssertFalse(step.applies(to: "unknown"))
    }

    func testEligibilityIsFailClosedAndSkipsOtherCivilizations() {
        let shared = makeBuild()
        let spanish = BuildOrder(id: "spanish-fc", name: "Spanish FC", civilizations: ["spanish"],
                                 map: "Арена", strategy: "Fast Castle", description: "Fixture",
                                 steps: [BuildStep(action: "Conquistadors")])
        XCTAssertTrue(BuildOrderLibrary.eligible([shared, spanish], civilizationID: nil).isEmpty)
        XCTAssertTrue(BuildOrderLibrary.eligible([shared, spanish], civilizationID: "unknown").isEmpty)
        XCTAssertEqual(BuildOrderLibrary.eligible([shared, spanish], civilizationID: "portuguese").map(\.id), [shared.id])
        XCTAssertEqual(BuildOrderLibrary.eligible([shared, spanish], civilizationID: "spanish").map(\.id), [spanish.id])
        XCTAssertTrue(BuildOrderLibrary.eligible([shared, spanish], civilizationID: "khitans").isEmpty)
    }

    func testLegacyAnyExpandsOnlyToKnownCatalog() throws {
        let json = """
        [{"id":"legacy-all","name":"Legacy","civilization":"Любая","map":"Арена",
          "strategy":"Fast Castle","description":"Legacy","steps":[{"action":"Start"}]}]
        """
        let build = try XCTUnwrap(BuildOrderLibrary.decode(Data(json.utf8)).first)
        XCTAssertEqual(build.civilizations, CivilizationCatalog.standard.map(\.id))
        XCTAssertFalse(build.supports(civilizationID: "future-unknown-civ"))
    }

    func testLegacyAliasesNormalizeButUnknownNamesAreRejected() throws {
        let build = makeBuild(civilizations: ["Турки", "Portuguese"], steps: [
            BuildStep(action: "Shared"),
            BuildStep(action: "Research Chemistry", exclude: ["Турки"])
        ])
        let decoded = try XCTUnwrap(BuildOrderLibrary.decode(JSONEncoder().encode([build])).first)
        XCTAssertEqual(decoded.civilizations, ["turks", "portuguese"])
        XCTAssertEqual(decoded.steps[1].exclude, ["turks"])

        let unknown = makeBuild(civilizations: ["Неизвестные"])
        XCTAssertThrowsError(try BuildOrderLibrary.decode(JSONEncoder().encode([unknown]))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Неизвестные"))
        }
    }

    func testTechnologyGoalsRoundTripAndInvalidGoalsAreRejected() throws {
        let technology = TechnologyGoal(technologyId: 101, label: "Feudal Age")
        let build = makeBuild(steps: [BuildStep(action: "Reach Feudal", technologyGoals: [technology])])
        let decoded = try XCTUnwrap(BuildOrderLibrary.decode(documentData(builds: [build])).first)
        XCTAssertEqual(decoded.steps[0].technologyGoals, [technology])

        for goals in [
            [TechnologyGoal(technologyId: 0, label: "Invalid")],
            [TechnologyGoal(technologyId: 101, label: " ")],
            [technology, technology],
            (1...9).map { TechnologyGoal(technologyId: $0, label: "Tech \($0)") }
        ] {
            XCTAssertThrowsError(try BuildOrderLibrary.validate([
                makeBuild(steps: [BuildStep(action: "Goal", technologyGoals: goals)])
            ]))
        }
    }

    func testUnsupportedVersionEmptyLibraryAndInvalidSourceAreRejected() throws {
        XCTAssertThrowsError(try BuildOrderLibrary.decode(documentData(version: 3)))
        XCTAssertThrowsError(try BuildOrderLibrary.decode(documentData(builds: [])))
        XCTAssertThrowsError(try BuildOrderLibrary.decode(Data("[]".utf8)))

        let badSource = BuildOrder(id: "bad-source", name: "Bad source", civilizations: ["turks"],
                                   map: "Арена", strategy: "Fast Imperial", description: "",
                                   steps: [BuildStep(action: "Start")],
                                   sources: [BuildSource(title: "Bad", url: "javascript:alert(1)")])
        XCTAssertThrowsError(try BuildOrderLibrary.validate([badSource]))
    }
}
