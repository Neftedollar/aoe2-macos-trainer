import Foundation

enum XSBuildExporter {
    enum ExportError: Error {
        case missingTemplate
        case invalidBuild
    }

    static func generate(for build: BuildOrder) throws -> String {
        guard !build.steps.isEmpty, build.steps.count <= 200 else {
            throw ExportError.invalidBuild
        }
        guard let url = Bundle.module.url(forResource: "trainer_template", withExtension: "xs"),
              let template = try? String(contentsOf: url, encoding: .utf8),
              template.contains("// @PLAN_SETUP@") else {
            throw ExportError.missingTemplate
        }

        let count = build.steps.count
        var lines = [
            "    trainerStepCount = \(count);",
            "    trainerStepTimes = xsArrayCreateInt(\(count), -1, \"trainer_step_times\");",
            "    trainerStepVillagers = xsArrayCreateInt(\(count), -1, \"trainer_step_villagers\");",
            "    trainerStepLabels = xsArrayCreateString(\(count), \"\", \"trainer_step_labels\");",
            "    xsArraySetString(trainerBuildNames, 0, \"\(escape(build.name))\");"
        ]

        for (index, step) in build.steps.enumerated() {
            let time = step.targetTimeSeconds ?? -1
            let villagers = step.targetVillagers ?? -1
            lines.append("    xsArraySetInt(trainerStepTimes, \(index), \(time));")
            lines.append("    xsArraySetInt(trainerStepVillagers, \(index), \(villagers));")
            // Keep in-game instruction lines compact for limited panel width.
            let title = String(step.action.prefix(80))
            lines.append("    xsArraySetString(trainerStepLabels, \(index), \"\(escape(title))\");")
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
