import Foundation
import XCTest
@testable import AoE2MacTrainer

/// Catalog regressions and production-time lower bounds, not a resource
/// simulation or evidence that the build has been completed in a real match.
final class KhitanBuildTests: XCTestCase {
    private func khitanBuild() throws -> BuildOrder {
        try XCTUnwrap(BuildOrderLibrary.bundled().first { $0.id == "khitans-scouts-pastures" })
    }

    private func deadline(forTechnology id: Int, in build: BuildOrder) throws -> Int {
        let step = try XCTUnwrap(build.steps.first {
            ($0.technologyGoals ?? []).contains { $0.technologyId == id }
        }, "Missing completed-technology checkpoint for \(id)")
        return try XCTUnwrap(step.targetTimeSeconds)
    }

    private func deadline(forObject id: Int, count: Int, in build: BuildOrder) throws -> Int {
        let step = try XCTUnwrap(build.steps.first {
            ($0.unitGoals ?? []).contains { $0.objectId == id && $0.count >= count }
        }, "Missing object checkpoint for \(count) of \(id)")
        return try XCTUnwrap(step.targetTimeSeconds)
    }

    func testStableIdentityAndKhitanOnlyEligibilityWithoutHuntGate() throws {
        let build = try khitanBuild()
        XCTAssertEqual(build.civilizations, ["khitans"])
        XCTAssertEqual(build.strategyFamily, "scouts")
        XCTAssertEqual(build.mapScriptFile, "Arabia.rms")
        XCTAssertTrue(build.startingFoodRequirements?.isEmpty ?? true,
                      "The base opening must remain available when deer have not been observed")

        for civilization in CivilizationCatalog.standard {
            XCTAssertEqual(build.supports(civilizationID: civilization.id), civilization.id == "khitans")
            XCTAssertEqual(build.resolved(for: civilization.id) != nil, civilization.id == "khitans")
        }
    }

    func testTwentyVillagersAndLoomPrecedeFeudalCompletion() throws {
        let build = try khitanBuild()
        let feudal = try deadline(forTechnology: 101, in: build)
        let loom = try deadline(forTechnology: 22, in: build)
        let twentyVillagers = try XCTUnwrap(build.steps.first { $0.targetVillagers == 20 })
        XCTAssertLessThan(try XCTUnwrap(twentyVillagers.targetTimeSeconds), feudal)
        XCTAssertLessThan(loom, feudal)
        XCTAssertLessThan(try deadline(forObject: 68, count: 1, in: build), feudal,
                          "The berry mill belongs in Dark Age, not a late pasture instruction")
    }

    func testDistinctScoutPastureAndCastleLancerMilestones() throws {
        let build = try khitanBuild()
        let feudal = try deadline(forTechnology: 101, in: build)
        let castle = try deadline(forTechnology: 102, in: build)
        let stable = try deadline(forObject: 101, count: 1, in: build)
        let scouts = try deadline(forObject: 448, count: 4, in: build)
        let pasture = try deadline(forObject: 1889, count: 1, in: build)
        let fourLancers = try deadline(forObject: 1370, count: 4, in: build)
        let eightLancers = try deadline(forObject: 1370, count: 8, in: build)

        XCTAssertGreaterThanOrEqual(stable, feudal)
        XCTAssertGreaterThan(scouts, stable)
        XCTAssertLessThan(scouts, castle)
        XCTAssertLessThan(pasture, castle)
        XCTAssertGreaterThan(fourLancers, castle)
        XCTAssertGreaterThan(eightLancers, fourLancers)
        XCTAssertTrue(build.steps.allSatisfy { $0.targetTimeSeconds != nil })
        XCTAssertTrue(build.hasValidGoalsAndTimeline)
    }

    func testUsesKhitanPastureAndMeleeUpgradesNotGenericKnightTechnologies() throws {
        let build = try khitanBuild()
        let technologies = Set(build.steps.flatMap { $0.technologyGoals ?? [] }.map(\.technologyId))
        let objects = Set(build.steps.flatMap { $0.unitGoals ?? [] }.map(\.objectId))

        XCTAssertTrue(technologies.isSuperset(of: [1014, 67, 68]),
                      "Require Domestication, Forging and Iron Casting in the cavalry plan")
        XCTAssertTrue(objects.isSuperset(of: [1889, 448, 1370]))
        let unavailableTechnologies: Set<Int> = [435, 14, 13, 12, 75]
        XCTAssertTrue(technologies.isDisjoint(with: unavailableTechnologies),
                      "No Bloodlines, Horse Collar, Heavy Plow, Crop Rotation or Blast Furnace")
        XCTAssertFalse(objects.contains(38), "Khitans cannot produce Knights")

        for step in build.steps where (step.targetTimeSeconds ?? 0) <= 25 * 60 {
            XCTAssertFalse((step.unitGoals ?? []).contains { $0.objectId == 1923 },
                           "Mounted Trebuchets are an Imperial follow-up, not this Castle opening")
        }
    }

    func testOneStableProductionHasTimeForScoutsLancersAndHusbandry() throws {
        let build = try khitanBuild()
        let stable = try deadline(forObject: 101, count: 1, in: build)
        let scouts = try deadline(forObject: 448, count: 4, in: build)
        // One starting scout plus three trained at 30 / 1.15 seconds each.
        let threeScoutSeconds = Int(ceil(3.0 * 30.0 / 1.15))
        XCTAssertGreaterThanOrEqual(scouts - stable, threeScoutSeconds)

        let castle = try deadline(forTechnology: 102, in: build)
        let husbandry = build.steps.first {
            ($0.technologyGoals ?? []).contains { $0.technologyId == 39 }
        }?.targetTimeSeconds
        for count in [4, 8] {
            let goal = try deadline(forObject: 1370, count: count, in: build)
            // The scout-line training bonus does not apply to Steppe Lancers.
            // Husbandry uses the same stable queue if required before this goal.
            let researchSeconds = husbandry.map { $0 <= goal ? 40 : 0 } ?? 0
            XCTAssertGreaterThanOrEqual(goal - castle, count * 24 + researchSeconds)
        }
    }

    func testExplicitSourceStatusAndPostLaunchBalanceReference() throws {
        let build = try khitanBuild()
        XCTAssertEqual(build.planStatus, "source-adapted")
        let sources = try XCTUnwrap(build.sources)
        XCTAssertTrue(sources.contains { $0.url.contains("update-169123") },
                      "Do not silently restore the pre-February-2026 pasture/scout assumptions")
        XCTAssertTrue(sources.contains { $0.url.contains("update-188329") },
                      "Record the reviewed patch baseline, not only the older balance nerf")
        XCTAssertTrue(sources.contains {
            $0.url.contains("/blob/e56728e76b7d08301fba7b18d5f16bc8554c109a/data/data.json")
        }, "Use the exact reviewed data snapshot rather than a moving master URL")
        XCTAssertTrue(sources.contains { $0.url.contains("jbraoe.wixsite.com") || $0.url.contains("youtube.com") })
    }
}
