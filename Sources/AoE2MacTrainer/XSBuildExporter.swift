import Foundation

enum XSBuildExporter {
    enum ExportError: Error {
        case missingTemplate
        case invalidBuild
    }

    static func generate(for build: BuildOrder) throws -> String {
        guard build.hasValidGoalsAndTimeline else {
            throw ExportError.invalidBuild
        }
        guard let url = Bundle.module.url(forResource: "trainer_template", withExtension: "xs"),
              let template = try? String(contentsOf: url, encoding: .utf8),
              template.contains("// @PLAN_SETUP@") else {
            throw ExportError.missingTemplate
        }

        let count = build.steps.count
        let unitGoalCount = build.steps.reduce(0) { $0 + ($1.unitGoals?.count ?? 0) }
        var lines = [
            "    trainerStepCount = \(count);",
            "    trainerStepTimes = xsArrayCreateInt(\(count), -1, \"trainer_step_times\");",
            "    trainerStepVillagers = xsArrayCreateInt(\(count), -1, \"trainer_step_villagers\");",
            "    trainerStepFood = xsArrayCreateInt(\(count), -1, \"trainer_step_food\");",
            "    trainerStepWood = xsArrayCreateInt(\(count), -1, \"trainer_step_wood\");",
            "    trainerStepGold = xsArrayCreateInt(\(count), -1, \"trainer_step_gold\");",
            "    trainerStepStone = xsArrayCreateInt(\(count), -1, \"trainer_step_stone\");",
            "    trainerStepDoneTimes = xsArrayCreateInt(\(count), -1, \"trainer_step_done_times\");",
            "    trainerStepLabels = xsArrayCreateString(\(count), \"\", \"trainer_step_labels\");",
            "    trainerUnitGoalCount = \(unitGoalCount);",
            "    trainerUnitGoalSteps = xsArrayCreateInt(\(max(1, unitGoalCount)), 0, \"trainer_unit_goal_steps\");",
            "    trainerUnitGoalObjects = xsArrayCreateInt(\(max(1, unitGoalCount)), 0, \"trainer_unit_goal_objects\");",
            "    trainerUnitGoalCounts = xsArrayCreateInt(\(max(1, unitGoalCount)), 0, \"trainer_unit_goal_counts\");",
            "    trainerUnitGoalLabels = xsArrayCreateString(\(max(1, unitGoalCount)), \"\", \"trainer_unit_goal_labels\");",
            "    xsArraySetString(trainerBuildNames, 0, \"\(escape(build.name))\");"
        ]

        var unitGoalIndex = 0
        for (index, step) in build.steps.enumerated() {
            let time = step.targetTimeSeconds ?? -1
            let villagers = step.targetVillagers ?? -1
            lines.append("    xsArraySetInt(trainerStepTimes, \(index), \(time));")
            lines.append("    xsArraySetInt(trainerStepVillagers, \(index), \(villagers));")
            if let allocation = step.allocation {
                lines.append("    xsArraySetInt(trainerStepFood, \(index), \(allocation.food));")
                lines.append("    xsArraySetInt(trainerStepWood, \(index), \(allocation.wood));")
                lines.append("    xsArraySetInt(trainerStepGold, \(index), \(allocation.gold));")
                lines.append("    xsArraySetInt(trainerStepStone, \(index), \(allocation.stone));")
            }
            // Keep in-game instruction lines compact for limited panel width.
            let title = String(step.action.prefix(80))
            lines.append("    xsArraySetString(trainerStepLabels, \(index), \"\(escape(title))\");")
            for goal in step.unitGoals ?? [] {
                lines.append("    xsArraySetInt(trainerUnitGoalSteps, \(unitGoalIndex), \(index));")
                lines.append("    xsArraySetInt(trainerUnitGoalObjects, \(unitGoalIndex), \(goal.objectId));")
                lines.append("    xsArraySetInt(trainerUnitGoalCounts, \(unitGoalIndex), \(goal.count));")
                lines.append("    xsArraySetString(trainerUnitGoalLabels, \(unitGoalIndex), \"\(escape(goal.label))\");")
                unitGoalIndex += 1
            }
        }

        return template.replacingOccurrences(of: "// @PLAN_SETUP@", with: lines.joined(separator: "\n"))
    }

    static func recommendedFileName(for build: BuildOrder) -> String {
        let slug = build.id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return "aoe2trainer_\(slug.isEmpty ? "custom" : slug).xs"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
