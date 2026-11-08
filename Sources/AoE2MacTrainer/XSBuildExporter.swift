import Foundation

/// Compiles a JSON catalog into a self-contained XS snapshot. The game, not
/// the macOS preview, chooses eligible builds using its actual civilization ID.
enum XSBuildExporter {
    /// XS source literals are ASCII-only. A localization-resource bundle would
    /// be a separate integration; JSON and the macOS UI retain original Unicode.
    static let textEncodingNotice = "В XS подписи пока выводятся транслитом. Оригинальный русский текст сохраняется в приложении и JSON."

    enum ExportError: LocalizedError {
        case missingTemplate
        case invalidBuild
        case catalogTooLarge

        var errorDescription: String? {
            switch self {
            case .missingTemplate:
                return "В приложении отсутствует шаблон XS-тренера."
            case .invalidBuild:
                return "Не удалось экспортировать каталог: проверь цивилизации, условия шагов и цели билдов."
            case .catalogTooLarge:
                return "Каталог для одного XS-модуля ограничен 128 билдами и 4096 шагами."
            }
        }
    }

    static func generate(for build: BuildOrder) throws -> String {
        try generate(builds: [build], preferredBuildID: build.id)
    }

    static func generate(builds: [BuildOrder], preferredBuildID: String? = nil) throws -> String {
        guard !builds.isEmpty,
              Set(builds.map(\.id)).count == builds.count,
              builds.allSatisfy(\.hasValidGoalsAndTimeline) else {
            throw ExportError.invalidBuild
        }

        let steps = builds.enumerated().flatMap { buildIndex, build in
            build.steps.map { (buildIndex: buildIndex, step: $0) }
        }
        guard builds.count <= 128, steps.count <= 4096 else {
            throw ExportError.catalogTooLarge
        }
        guard let url = Bundle.module.url(forResource: "trainer_template", withExtension: "xs"),
              let template = try? String(contentsOf: url, encoding: .utf8),
              template.contains("// @CATALOG_SETUP@") else {
            throw ExportError.missingTemplate
        }

        // Numeric XS IDs are the interoperability boundary; translated names
        // are never compared with a game's localized UI strings.
        func xsID(_ civilization: String) throws -> Int {
            guard let definition = CivilizationCatalog.resolve(civilization) else {
                throw ExportError.invalidBuild
            }
            return definition.xsID
        }

        var allowed: [(build: Int, civ: Int)] = []
        for (index, build) in builds.enumerated() {
            for civilization in build.civilizations {
                allowed.append((index, try xsID(civilization)))
            }
        }
        var included: [(step: Int, civ: Int)] = []
        var excluded: [(step: Int, civ: Int)] = []
        for (index, entry) in steps.enumerated() {
            for civilization in entry.step.includeOnly ?? [] {
                included.append((index, try xsID(civilization)))
            }
            for civilization in entry.step.exclude ?? [] {
                excluded.append((index, try xsID(civilization)))
            }
        }
        let unitGoalCount = steps.reduce(0) { $0 + ($1.step.unitGoals?.count ?? 0) }
        let techGoalCount = steps.reduce(0) { $0 + ($1.step.technologyGoals?.count ?? 0) }
        let maxBuildSteps = builds.map { $0.steps.count }.max() ?? 1
        let preferredIndex = preferredBuildID.flatMap { id in builds.firstIndex { $0.id == id } } ?? -1

        var lines = [
            "    trainerBuildCount = \(builds.count);",
            "    trainerPreferredBuild = \(preferredIndex);",
            "    trainerStepCount = \(steps.count);",
            "    trainerAllowedPairCount = \(allowed.count);",
            "    trainerIncludedPairCount = \(included.count);",
            "    trainerExcludedPairCount = \(excluded.count);"
        ]
        func intArray(_ variable: String, _ count: Int, _ defaultValue: Int = -1) {
            lines.append("    \(variable) = xsArrayCreateInt(\(max(1, count)), \(defaultValue), \"\(variable)\");")
        }
        func boolArray(_ variable: String, _ count: Int) {
            lines.append("    \(variable) = xsArrayCreateBool(\(max(1, count)), false, \"\(variable)\");")
        }
        func stringArray(_ variable: String, _ count: Int) {
            lines.append("    \(variable) = xsArrayCreateString(\(max(1, count)), \"\", \"\(variable)\");")
        }
        func setInt(_ variable: String, _ index: Int, _ value: Int) {
            lines.append("    xsArraySetInt(\(variable), \(index), \(value));")
        }
        var hasTransliteratedText = false
        func setString(_ variable: String, _ index: Int, _ value: String) {
            if value.unicodeScalars.contains(where: { $0.value > 127 }) {
                hasTransliteratedText = true
            }
            lines.append("    xsArraySetString(\(variable), \(index), \"\(escape(asciiText(value)))\");")
        }

        stringArray("trainerBuildNames", builds.count)
        stringArray("trainerBuildMaps", builds.count)
        boolArray("trainerBuildEnabled", builds.count)
        intArray("trainerEligibleBuilds", builds.count)
        intArray("trainerSelectedSteps", maxBuildSteps)
        intArray("trainerAllowedBuilds", allowed.count)
        intArray("trainerAllowedCivilizations", allowed.count)
        intArray("trainerIncludedSteps", included.count)
        intArray("trainerIncludedCivilizations", included.count)
        intArray("trainerExcludedSteps", excluded.count)
        intArray("trainerExcludedCivilizations", excluded.count)

        for variable in ["trainerStepBuilds", "trainerStepTimes", "trainerStepVillagers",
                         "trainerStepFood", "trainerStepWood", "trainerStepGold", "trainerStepStone",
                         "trainerStepDoneTimes", "trainerStepUnitStarts", "trainerStepUnitCounts",
                         "trainerStepTechStarts", "trainerStepTechCounts"] {
            intArray(variable, steps.count)
        }
        boolArray("trainerStepEnabled", steps.count)
        boolArray("trainerStepUsesIncludeOnly", steps.count)
        stringArray("trainerStepLabels", steps.count)
        intArray("trainerUnitGoalObjects", unitGoalCount)
        intArray("trainerUnitGoalCounts", unitGoalCount)
        stringArray("trainerUnitGoalLabels", unitGoalCount)
        intArray("trainerTechGoalIDs", techGoalCount)
        stringArray("trainerTechGoalLabels", techGoalCount)

        for (index, build) in builds.enumerated() {
            setString("trainerBuildNames", index, build.name)
            setString("trainerBuildMaps", index, build.map)
        }
        for (index, pair) in allowed.enumerated() {
            setInt("trainerAllowedBuilds", index, pair.build)
            setInt("trainerAllowedCivilizations", index, pair.civ)
        }
        for (index, pair) in included.enumerated() {
            setInt("trainerIncludedSteps", index, pair.step)
            setInt("trainerIncludedCivilizations", index, pair.civ)
        }
        for (index, pair) in excluded.enumerated() {
            setInt("trainerExcludedSteps", index, pair.step)
            setInt("trainerExcludedCivilizations", index, pair.civ)
        }

        var unitGoalIndex = 0
        var techGoalIndex = 0
        for (index, entry) in steps.enumerated() {
            let step = entry.step
            setInt("trainerStepBuilds", index, entry.buildIndex)
            setInt("trainerStepTimes", index, step.targetTimeSeconds ?? -1)
            setInt("trainerStepVillagers", index, step.targetVillagers ?? -1)
            setInt("trainerStepFood", index, step.allocation?.food ?? -1)
            setInt("trainerStepWood", index, step.allocation?.wood ?? -1)
            setInt("trainerStepGold", index, step.allocation?.gold ?? -1)
            setInt("trainerStepStone", index, step.allocation?.stone ?? -1)
            if step.includeOnly != nil {
                lines.append("    xsArraySetBool(trainerStepUsesIncludeOnly, \(index), true);")
            }
            // Instruction panels are narrow; the complete source remains in JSON.
            setString("trainerStepLabels", index, String(step.action.prefix(120)))
            setInt("trainerStepUnitStarts", index, unitGoalIndex)
            setInt("trainerStepUnitCounts", index, step.unitGoals?.count ?? 0)
            for goal in step.unitGoals ?? [] {
                setInt("trainerUnitGoalObjects", unitGoalIndex, goal.objectId)
                setInt("trainerUnitGoalCounts", unitGoalIndex, goal.count)
                setString("trainerUnitGoalLabels", unitGoalIndex, goal.label)
                unitGoalIndex += 1
            }
            setInt("trainerStepTechStarts", index, techGoalIndex)
            setInt("trainerStepTechCounts", index, step.technologyGoals?.count ?? 0)
            for goal in step.technologyGoals ?? [] {
                setInt("trainerTechGoalIDs", techGoalIndex, goal.technologyId)
                setString("trainerTechGoalLabels", techGoalIndex, goal.label)
                techGoalIndex += 1
            }
        }

        lines.append("    trainerUsesASCIIText = \(hasTransliteratedText ? "true" : "false");")
        return template.replacingOccurrences(of: "// @CATALOG_SETUP@", with: lines.joined(separator: "\n"))
    }

    static func recommendedFileName(for build: BuildOrder) -> String {
        let slug = build.id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return "aoe2trainer_\(slug.isEmpty ? "custom" : slug).xs"
    }

    /// Transliterate labels rather than silently dropping unsupported text.
    /// Untransliterable symbols remain visible as explicit [U+XXXX] markers.
    /// This changes only emitted XS; the source BuildOrder is never modified.
    private static func asciiText(_ value: String) -> String {
        let punctuation: [(String, String)] = [
            ("↔", "<->"), ("→", "->"), ("←", "<-"), ("⇒", "=>"),
            ("—", "-"), ("–", "-"), ("−", "-"), ("…", "..."), ("×", "x"),
            ("“", "\""), ("”", "\""), ("„", "\""), ("«", "\""), ("»", "\""),
            ("‘", "'"), ("’", "'"), ("‚", "'"), ("ʹ", "'")
        ]
        var text = value
        for (original, replacement) in punctuation {
            text = text.replacingOccurrences(of: original, with: replacement)
        }
        text = text.applyingTransform(.toLatin, reverse: false) ?? text
        text = text.applyingTransform(.stripCombiningMarks, reverse: false) ?? text
        // Transliteration can introduce modifier-letter primes.
        text = text.replacingOccurrences(of: "ʹ", with: "'")
            .replacingOccurrences(of: "ʺ", with: "\"")
        return text.unicodeScalars.map { scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return " " }
            if (32...126).contains(scalar.value) { return String(scalar) }
            let hex = String(scalar.value, radix: 16, uppercase: true)
            return "[U+" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex + "]"
        }.joined()
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
