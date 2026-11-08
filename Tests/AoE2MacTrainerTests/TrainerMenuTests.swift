import AppKit
import XCTest
@testable import AoE2MacTrainer

final class TrainerMenuTests: XCTestCase {
    @MainActor
    func testChoosingAndClearingFoodInTheNativeMenu() throws {
        let state = TrainerState(builds: try BuildOrderLibrary.bundled())
        let delegate = TrainerAppDelegate(state: state)
        let menu = delegate.makeMenu()
        let food = try XCTUnwrap(menu.item(withTitle: "Дичь на старте")?.submenu)
        let kinds = StartingFoodKind.allCases
        XCTAssertEqual(food.items.map(\.title), kinds.map(\.displayName))

        func choose(_ kind: StartingFoodKind, _ value: Int) throws {
            let submenu = try XCTUnwrap(food.items.first { $0.title.hasPrefix(kind.displayName) }?.submenu)
            let item = try XCTUnwrap(submenu.item(withTag: value))
            XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        }

        for kind in food.items {
            let counts = try XCTUnwrap(kind.submenu)
            XCTAssertEqual(counts.items.map(\.title), [
                "Неизвестно", "1 животное", "2 животных", "3 животных", "4 животных", "5 животных", "6 животных"
            ])
            XCTAssertEqual(counts.items.filter { $0.state == .on }.map(\.tag), [0])
        }

        try choose(.pushableHunt, 5)
        try choose(.smallGame, 2)
        XCTAssertEqual(state.previewFoodEvidence, StartingFoodEvidence(pushableHuntCount: 5, smallGameCount: 2))
        XCTAssertEqual(food.items.map(\.title), ["Дичь для подгона к ТЦ · 5", "Мелкая дичь · 2"])
        try choose(.pushableHunt, 0)
        XCTAssertEqual(state.previewFoodEvidence, StartingFoodEvidence(smallGameCount: 2))
        XCTAssertEqual(food.items.compactMap { $0.submenu?.items.first { $0.state == .on }?.tag }, [0, 2])
    }

    @MainActor
    func testCustomFoodRequirementsAreReachableThroughTheMenu() throws {
        let plan = BuildOrder(id: "custom", name: "Особая охота", civilizations: ["portuguese"],
                              map: "Arena", strategy: "FC", description: "Учебный билд",
                              steps: [BuildStep(action: "Start", targetTimeSeconds: 0)],
                              startingFoodRequirements: [.init(kind: .smallGame, minCount: 32)])
        let state = TrainerState(builds: [plan])
        state.selectPreviewCivilization("portuguese")
        let delegate = TrainerAppDelegate(state: state)
        let menu = delegate.makeMenu()
        let food = try XCTUnwrap(menu.item(withTitle: "Дичь на старте")?.submenu)
        let smallGame = try XCTUnwrap(food.item(withTitle: "Мелкая дичь")?.submenu)
        let target = try XCTUnwrap(smallGame.item(withTag: 32))
        XCTAssertEqual(target.title, "32 животных")
        XCTAssertTrue(state.builds.isEmpty)
        XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(target.action), to: target.target, from: target))
        XCTAssertEqual(state.builds.map(\.id), ["custom"])
    }

    @MainActor
    func testMatchAutomaticallyUpdatesMenuAndStartsAFreshSession() throws {
        let state = TrainerState(builds: try BuildOrderLibrary.bundled())
        state.selectPreviewCivilization("franks")
        let delegate = TrainerAppDelegate(state: state)
        let menu = delegate.makeMenu()
        let choices = try XCTUnwrap(menu.item(withTitle: "Цивилизация")?.submenu)

        let first = FeralMatch(id: "first", civilizationID: "portuguese")
        delegate.updateMatch(first)
        XCTAssertEqual(menu.items.first?.title, "Матч подключён · Португальцы")
        XCTAssertEqual(choices.items.map(\.title), ["Португальцы"])
        XCTAssertTrue(try XCTUnwrap(state.selectedBuild).supports(civilizationID: "portuguese"))
        state.selectPreviewCivilization("turks")
        XCTAssertEqual(state.previewCivilizationID, "portuguese")
        state.updatePreviewFoodEvidence(StartingFoodEvidence(smallGameCount: 3))
        state.next()
        state.toggleClock()

        delegate.updateMatch(first)
        XCTAssertEqual(state.stepIndex, 1)
        XCTAssertTrue(state.clockRunning)
        delegate.updateMatch(FeralMatch(id: "second", civilizationID: "portuguese"))
        XCTAssertEqual(state.stepIndex, 0)
        XCTAssertFalse(state.clockRunning)
        XCTAssertEqual(state.previewFoodEvidence, .unknown)

        delegate.updateMatch(FeralMatch(id: "third", civilizationID: nil))
        XCTAssertNil(state.selectedBuild)
        XCTAssertNil(state.previewCivilizationID)
        delegate.updateMatch(FeralMatch(id: "third", civilizationID: "turks"))
        XCTAssertEqual(state.previewCivilizationID, "turks")
        delegate.updateMatch(nil)
        XCTAssertEqual(state.previewCivilizationID, "franks")
        XCTAssertEqual(menu.items.first?.title, "Ожидание матча · предпросмотр")
        XCTAssertGreaterThan(choices.items.count, 1)
    }
}
