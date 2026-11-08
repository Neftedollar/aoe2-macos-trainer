import Foundation

struct ResourceAllocation: Codable, Equatable {
    let food: Int
    let wood: Int
    let gold: Int
    let stone: Int

    var isValid: Bool { [food, wood, gold, stone].allSatisfy { $0 >= 0 } }
}

struct BuildSource: Codable, Equatable {
    let title: String
    let url: String

    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let components = URLComponents(string: url),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty else { return false }
        return true
    }
}

/// A minimum number of currently owned objects of a specific AoE2 object ID.
/// Buildings and units share the same IDs in the XS API.
struct UnitGoal: Codable, Equatable {
    let objectId: Int
    let count: Int
    let label: String

    var isValid: Bool { objectId > 0 && count > 0 && !label.isEmpty }
}

/// A completed technology, including age advancement. Queued/researching is
/// deliberately not treated as completed by the XS trainer.
struct TechnologyGoal: Codable, Equatable {
    let technologyId: Int
    let label: String

    var isValid: Bool {
        technologyId > 0 && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct BuildStep: Codable, Equatable {
    let action: String
    let targetVillagers: Int?
    let targetTimeSeconds: Int?
    let allocation: ResourceAllocation?
    let note: String?
    let unitGoals: [UnitGoal]?
    /// Optional allowlist, further restricted by `exclude`. Values are canonical
    /// civilization IDs, never localized labels in a validated v2 document.
    let includeOnly: [String]?
    let exclude: [String]?
    let technologyGoals: [TechnologyGoal]?

    init(
        action: String,
        targetVillagers: Int? = nil,
        targetTimeSeconds: Int? = nil,
        allocation: ResourceAllocation? = nil,
        note: String? = nil,
        unitGoals: [UnitGoal]? = nil,
        includeOnly: [String]? = nil,
        exclude: [String]? = nil,
        technologyGoals: [TechnologyGoal]? = nil
    ) {
        self.action = action
        self.targetVillagers = targetVillagers
        self.targetTimeSeconds = targetTimeSeconds
        self.allocation = allocation
        self.note = note
        self.unitGoals = unitGoals
        self.includeOnly = includeOnly?.map { CivilizationCatalog.resolve($0)?.id ?? $0 }
        self.exclude = exclude?.map { CivilizationCatalog.resolve($0)?.id ?? $0 }
        self.technologyGoals = technologyGoals
    }

    func applies(to civilizationID: String) -> Bool {
        guard let canonical = CivilizationCatalog.resolve(civilizationID)?.id else { return false }
        return (includeOnly?.contains(canonical) ?? true) && !(exclude?.contains(canonical) ?? false)
    }

    /// Conditions have already been evaluated for this specialized copy.
    fileprivate var unconditional: BuildStep {
        BuildStep(action: action, targetVillagers: targetVillagers,
                  targetTimeSeconds: targetTimeSeconds, allocation: allocation,
                  note: note, unitGoals: unitGoals, technologyGoals: technologyGoals)
    }

    var isValid: Bool {
        !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (targetVillagers ?? 0) >= 0 && (targetTimeSeconds ?? 0) >= 0 &&
            (allocation?.isValid ?? true) &&
            (unitGoals?.count ?? 0) <= 8 &&
            (unitGoals?.allSatisfy(\.isValid) ?? true) &&
            Set((unitGoals ?? []).map(\.objectId)).count == (unitGoals?.count ?? 0) &&
            (technologyGoals?.count ?? 0) <= 8 &&
            (technologyGoals?.allSatisfy(\.isValid) ?? true) &&
            Set((technologyGoals ?? []).map(\.technologyId)).count == (technologyGoals?.count ?? 0)
    }
}

struct BuildOrder: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let civilizations: [String]
    let map: String
    /// Optional standard RMS filename from the game's own bundled scripts.
    let mapScriptFile: String?
    let strategy: String
    let description: String
    let steps: [BuildStep]
    let sources: [BuildSource]?
    let planStatus: String?
    /// Stable grouping ID for independently selectable variants, e.g. fast-castle.
    let strategyFamily: String?
    /// Positive observed-food requirements. Omitted/empty means a generic plan.
    let startingFoodRequirements: [StartingFoodRequirement]?

    // Legacy property retained for existing UI call sites and integrations.
    var civilization: String {
        civilizations.map { CivilizationCatalog.resolve($0)?.name ?? $0 }.joined(separator: ", ")
    }

    init(id: String, name: String, civilizations: [String], map: String,
         mapScriptFile: String? = nil, strategy: String, description: String, steps: [BuildStep],
         sources: [BuildSource]? = nil, planStatus: String? = nil,
         strategyFamily: String? = nil, startingFoodRequirements: [StartingFoodRequirement]? = nil) {
        self.id = id
        self.name = name
        self.civilizations = civilizations.map { CivilizationCatalog.resolve($0)?.id ?? $0 }
        self.map = map
        self.mapScriptFile = mapScriptFile
        self.strategy = strategy
        self.description = description
        self.steps = steps
        self.sources = sources
        self.planStatus = planStatus
        self.strategyFamily = strategyFamily
        self.startingFoodRequirements = startingFoodRequirements
    }

    init(id: String, name: String, civilization: String, map: String,
         mapScriptFile: String? = nil, strategy: String, description: String, steps: [BuildStep],
         sources: [BuildSource]? = nil, planStatus: String? = nil,
         strategyFamily: String? = nil, startingFoodRequirements: [StartingFoodRequirement]? = nil) {
        // Older call sites may pass the legacy comma-separated display label.
        let names = civilization.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        self.init(id: id, name: name, civilizations: names, map: map,
                  mapScriptFile: mapScriptFile, strategy: strategy, description: description,
                  steps: steps, sources: sources, planStatus: planStatus,
                  strategyFamily: strategyFamily, startingFoodRequirements: startingFoodRequirements)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, civilizations, civilization, map, mapScriptFile, strategy, description, steps
        case sources, planStatus, strategyFamily, startingFoodRequirements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        if decoder.userInfo[.strictBuildLibraryV2] as? Bool == true {
            civilizations = try c.decode([String].self, forKey: .civilizations)
        } else if let names = try c.decodeIfPresent([String].self, forKey: .civilizations) {
            civilizations = names
        } else if let names = try? c.decode([String].self, forKey: .civilization) {
            civilizations = names
        } else {
            civilizations = [try c.decode(String.self, forKey: .civilization)]
        }
        map = try c.decode(String.self, forKey: .map)
        mapScriptFile = try c.decodeIfPresent(String.self, forKey: .mapScriptFile)
        strategy = try c.decode(String.self, forKey: .strategy)
        description = try c.decode(String.self, forKey: .description)
        steps = try c.decode([BuildStep].self, forKey: .steps)
        sources = try c.decodeIfPresent([BuildSource].self, forKey: .sources)
        planStatus = try c.decodeIfPresent(String.self, forKey: .planStatus)
        strategyFamily = try c.decodeIfPresent(String.self, forKey: .strategyFamily)
        startingFoodRequirements = try c.decodeIfPresent([StartingFoodRequirement].self, forKey: .startingFoodRequirements)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(civilizations, forKey: .civilizations)
        try c.encode(map, forKey: .map)
        try c.encodeIfPresent(mapScriptFile, forKey: .mapScriptFile)
        try c.encode(strategy, forKey: .strategy)
        try c.encode(description, forKey: .description)
        try c.encode(steps, forKey: .steps)
        try c.encodeIfPresent(sources, forKey: .sources)
        try c.encodeIfPresent(planStatus, forKey: .planStatus)
        try c.encodeIfPresent(strategyFamily, forKey: .strategyFamily)
        try c.encodeIfPresent(startingFoodRequirements, forKey: .startingFoodRequirements)
    }

    func supports(civilizationID: String) -> Bool {
        guard let canonical = CivilizationCatalog.resolve(civilizationID)?.id else { return false }
        return civilizations.contains(canonical)
    }

    /// Resolve from the ORIGINAL catalog on every civilization change. The
    /// result is a specialized plan, not another multi-civilization template.
    func resolved(for civilizationID: String) -> BuildOrder? {
        guard let canonical = CivilizationCatalog.resolve(civilizationID)?.id,
              supports(civilizationID: canonical) else { return nil }
        let activeSteps = steps.filter { $0.applies(to: canonical) }.map(\.unconditional)
        guard !activeSteps.isEmpty else { return nil }
        return BuildOrder(id: id, name: name, civilizations: [canonical], map: map,
                          mapScriptFile: mapScriptFile, strategy: strategy, description: description,
                          steps: activeSteps, sources: sources, planStatus: planStatus,
                          strategyFamily: strategyFamily, startingFoodRequirements: startingFoodRequirements)
    }

    var hasValidGoalsAndTimeline: Bool {
        validationIssue(declaredCivilizations: Set(CivilizationCatalog.standard.map(\.id))) == nil
    }

    fileprivate func validationIssue(declaredCivilizations: Set<String>) -> String? {
        let context = "Билд «\(id)»"
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !map.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !strategy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "\(context): id, name, map и strategy не могут быть пустыми."
        }
        if let family = strategyFamily {
            let segments = family.split(separator: "-", omittingEmptySubsequences: false)
            let isKebabID = !family.isEmpty && segments.allSatisfy { segment in
                !segment.isEmpty && segment.utf8.allSatisfy { byte in
                    (97...122).contains(byte) || (48...57).contains(byte)
                }
            }
            guard isKebabID else {
                return "\(context): strategyFamily должен быть непустым kebab-case ID, например fast-castle."
            }
        }
        if let requirements = startingFoodRequirements {
            guard requirements.allSatisfy(\.isValid) else {
                return "\(context): startingFoodRequirements.minCount должен быть целым числом от 1 до 32."
            }
            guard Set(requirements.map(\.kind)).count == requirements.count else {
                return "\(context): в startingFoodRequirements повторяется один и тот же kind."
            }
        }
        if let file = mapScriptFile,
           !(file.lowercased().hasSuffix(".rms") && file.allSatisfy({
               $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".")
           })) {
            return "\(context): mapScriptFile должен быть именем файла .rms без пути, пробелов и кавычек."
        }
        guard !civilizations.isEmpty else { return "\(context): civilizations не может быть пустым." }
        guard Set(civilizations).count == civilizations.count else {
            return "\(context): в civilizations повторяется одна и та же цивилизация."
        }
        for civilization in civilizations {
            guard CivilizationCatalog.resolve(civilization)?.id == civilization else {
                return "\(context): неизвестный канонический ID цивилизации «\(civilization)»."
            }
            guard declaredCivilizations.contains(civilization) else {
                return "\(context): цивилизация «\(civilization)» не объявлена в civilizations документа."
            }
        }
        guard !steps.isEmpty, steps.count <= 200 else {
            return "\(context): нужно от 1 до 200 шагов."
        }
        let allowed = Set(civilizations)
        for (index, step) in steps.enumerated() {
            let stepContext = "\(context), шаг \(index + 1)"
            guard step.isValid else {
                return "\(stepContext): проверь текст действия, неотрицательные цели, уникальные objectId/technologyId (не более 8 unitGoals и 8 technologyGoals)."
            }
            if let include = step.includeOnly, include.isEmpty {
                return "\(stepContext): includeOnly не может быть пустым; убери поле для общего шага."
            }
            for (field, references) in [("includeOnly", step.includeOnly), ("exclude", step.exclude)] {
                guard let references else { continue }
                guard Set(references).count == references.count else {
                    return "\(stepContext): поле \(field) содержит повторяющиеся цивилизации."
                }
                for reference in references {
                    guard CivilizationCatalog.resolve(reference)?.id == reference else {
                        return "\(stepContext): неизвестный канонический ID «\(reference)» в \(field)."
                    }
                    guard allowed.contains(reference) else {
                        return "\(stepContext): «\(reference)» из \(field) не объявлена в civilizations этого билда."
                    }
                }
            }
        }
        // Mutually exclusive variants may have different deadlines. The order
        // must be chronological for every plan a player can actually receive.
        for civilization in civilizations {
            let activeSteps = steps.filter { $0.applies(to: civilization) }
            guard !activeSteps.isEmpty else {
                return "\(context): после includeOnly/exclude для «\(civilization)» не осталось шагов."
            }
            var lastDeadline = -1
            for step in activeSteps {
                if let time = step.targetTimeSeconds {
                    guard time >= lastDeadline else {
                        return "\(context): targetTimeSeconds идут не по порядку для «\(civilization)»."
                    }
                    lastDeadline = time
                }
            }
        }
        if sources?.contains(where: { !$0.isValid }) == true {
            return "\(context): у каждого sources нужны непустой title и корректный http(s) URL."
        }
        if let status = planStatus, status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(context): planStatus не может быть пустой строкой."
        }
        return nil
    }
}

struct BuildOrderDocument: Codable, Equatable {
    let schemaVersion: Int
    let civilizations: [CivilizationDefinition]
    let builds: [BuildOrder]
}

private extension CodingUserInfoKey {
    static let strictBuildLibraryV2 = CodingUserInfoKey(rawValue: "AoE2MacTrainer.strictBuildLibraryV2")!
}

enum BuildOrderLibrary {
    static var customBuildsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AoE2MacTrainer", isDirectory: true)
            .appendingPathComponent("builds.json")
    }

    static func decode(_ data: Data) throws -> [BuildOrder] {
        try decodeDocument(data).builds
    }

    /// All successful decodes return a canonical v2 document, including imports
    /// of the original array format. Unknown references never expand to "all".
    static func decodeDocument(_ data: Data) throws -> BuildOrderDocument {
        try parse(data, allowEmpty: false)
    }

    static func validate(_ builds: [BuildOrder]) throws {
        try validate(builds, declaredCivilizations: Set(CivilizationCatalog.standard.map(\.id)),
                     allowEmpty: false)
    }

    /// Unknown/missing civilization is intentionally fail-closed. Keep the
    /// original catalog and call this again when the observed civ changes.
    static func eligible(_ builds: [BuildOrder], civilizationID: String?,
                         startingFoodEvidence: StartingFoodEvidence = .unknown) -> [BuildOrder] {
        guard let civilizationID,
              let canonical = CivilizationCatalog.resolve(civilizationID)?.id else { return [] }
        return builds.filter { startingFoodEvidence.satisfies(requirements: $0.startingFoodRequirements ?? []) }
            .compactMap { $0.resolved(for: canonical) }
    }

    private static func parse(_ data: Data, allowEmpty: Bool) throws -> BuildOrderDocument {
        let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let decoder = JSONDecoder()
        let document: BuildOrderDocument
        if root is [Any] {
            let legacy = try decoder.decode([BuildOrder].self, from: data)
            document = BuildOrderDocument(
                schemaVersion: 2, civilizations: CivilizationCatalog.standard,
                builds: try legacy.map(normalizeLegacy)
            )
        } else if let object = root as? [String: Any] {
            try validateV2Keys(object)
            decoder.userInfo[.strictBuildLibraryV2] = true
            document = try decoder.decode(BuildOrderDocument.self, from: data)
            guard document.schemaVersion == 2 else {
                throw LibraryError.invalidDocument("Неизвестная schemaVersion \(document.schemaVersion); поддерживается версия 2.")
            }
        } else {
            throw LibraryError.invalidDocument("Корень JSON должен быть документом версии 2 или массивом билдов старого формата.")
        }

        try validateDeclarations(document.civilizations)
        try validate(document.builds,
                     declaredCivilizations: Set(document.civilizations.map(\.id)),
                     allowEmpty: allowEmpty)
        return document
    }

    /// Codable intentionally ignores unknown keys. For editable v2 plans that
    /// would make a typo such as `exlclude` silently remove a civilization
    /// restriction, so reject unknown fields before decoding any typed models.
    /// Legacy arrays remain permissive for compatibility with older exports.
    private static func validateV2Keys(_ root: [String: Any]) throws {
        func check(_ object: [String: Any], allowed: Set<String>, path: String,
                   context: String = "") throws {
            if let unknown = Set(object.keys).subtracting(allowed).sorted().first {
                throw LibraryError.invalidDocument(
                    "\(path)\(context): неизвестное поле «\(unknown)». Допустимые поля: \(allowed.sorted().joined(separator: ", "))."
                )
            }
        }

        func requireArrayIfPresent(_ object: [String: Any], key: String,
                                   path: String, context: String) throws {
            guard let value = object[key] else { return }
            guard value is [Any] else {
                throw LibraryError.invalidDocument(
                    "\(path).\(key)\(context): поле должно быть массивом; убери поле, если условие не требуется."
                )
            }
        }

        try check(root, allowed: ["schemaVersion", "civilizations", "builds"], path: "$")
        for (index, declaration) in ((root["civilizations"] as? [[String: Any]]) ?? []).enumerated() {
            try check(declaration, allowed: ["id", "name", "xsID"], path: "$.civilizations[\(index)]")
        }
        for (buildIndex, build) in ((root["builds"] as? [[String: Any]]) ?? []).enumerated() {
            let buildPath = "$.builds[\(buildIndex)]"
            let context = (build["id"] as? String).map { " (билд «\($0)»)" } ?? ""
            try check(build, allowed: ["id", "name", "civilizations", "map", "mapScriptFile",
                                       "strategy", "description", "steps", "sources", "planStatus",
                                       "strategyFamily", "startingFoodRequirements"],
                      path: buildPath, context: context)
            // decodeIfPresent treats JSON null as an omitted condition. That
            // would silently loosen a hand-edited restriction, so v2 fields
            // must have their declared type whenever the key is present.
            try requireArrayIfPresent(build, key: "startingFoodRequirements",
                                      path: buildPath, context: context)
            if let family = build["strategyFamily"], !(family is String) {
                throw LibraryError.invalidDocument(
                    "\(buildPath).strategyFamily\(context): поле должно быть непустым строковым kebab-case ID."
                )
            }
            for (requirementIndex, requirement) in ((build["startingFoodRequirements"] as? [[String: Any]]) ?? []).enumerated() {
                try check(requirement, allowed: ["kind", "minCount"],
                          path: "\(buildPath).startingFoodRequirements[\(requirementIndex)]", context: context)
            }
            for (sourceIndex, source) in ((build["sources"] as? [[String: Any]]) ?? []).enumerated() {
                try check(source, allowed: ["title", "url"], path: "\(buildPath).sources[\(sourceIndex)]",
                          context: context)
            }
            for (stepIndex, step) in ((build["steps"] as? [[String: Any]]) ?? []).enumerated() {
                let stepPath = "\(buildPath).steps[\(stepIndex)]"
                try check(step, allowed: ["action", "targetVillagers", "targetTimeSeconds", "allocation",
                                          "note", "unitGoals", "includeOnly", "exclude", "technologyGoals"],
                          path: stepPath, context: context)
                for selector in ["includeOnly", "exclude"] {
                    try requireArrayIfPresent(step, key: selector, path: stepPath, context: context)
                }
                if let allocation = step["allocation"] as? [String: Any] {
                    try check(allocation, allowed: ["food", "wood", "gold", "stone"],
                              path: "\(stepPath).allocation", context: context)
                }
                for (goalIndex, goal) in ((step["unitGoals"] as? [[String: Any]]) ?? []).enumerated() {
                    try check(goal, allowed: ["objectId", "count", "label"],
                              path: "\(stepPath).unitGoals[\(goalIndex)]", context: context)
                }
                for (goalIndex, goal) in ((step["technologyGoals"] as? [[String: Any]]) ?? []).enumerated() {
                    try check(goal, allowed: ["technologyId", "label"],
                              path: "\(stepPath).technologyGoals[\(goalIndex)]", context: context)
                }
            }
        }
    }

    private static func validateDeclarations(_ declarations: [CivilizationDefinition]) throws {
        guard !declarations.isEmpty else {
            throw LibraryError.invalidDocument("В начале документа должен быть непустой список civilizations.")
        }
        var ids = Set<String>()
        var engineIDs = Set<Int>()
        for civilization in declarations {
            guard ids.insert(civilization.id).inserted else {
                throw LibraryError.invalidDocument("Цивилизация «\(civilization.id)» объявлена повторно.")
            }
            guard engineIDs.insert(civilization.xsID).inserted else {
                throw LibraryError.invalidDocument("ID движка xsID=\(civilization.xsID) объявлен повторно.")
            }
            guard let known = CivilizationCatalog.resolve(civilization.id), known.id == civilization.id else {
                throw LibraryError.invalidDocument("В civilizations объявлен неизвестный канонический ID «\(civilization.id)».")
            }
            guard known.xsID == civilization.xsID else {
                throw LibraryError.invalidDocument("Для «\(civilization.id)» ожидается xsID=\(known.xsID), а указан \(civilization.xsID).")
            }
            guard !civilization.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibraryError.invalidDocument("У цивилизации «\(civilization.id)» отсутствует name.")
            }
        }
    }

    private static func validate(_ builds: [BuildOrder], declaredCivilizations: Set<String>,
                                 allowEmpty: Bool) throws {
        if !allowEmpty && builds.isEmpty { throw LibraryError.emptyBuild }
        guard Set(builds.map(\.id)).count == builds.count else { throw LibraryError.duplicateID }
        for build in builds {
            if let issue = build.validationIssue(declaredCivilizations: declaredCivilizations) {
                throw LibraryError.invalidDocument(issue)
            }
        }
    }

    private static func legacyIDs(_ references: [String], context: String,
                                  allowAny: Bool = false) throws -> [String] {
        // Old singular labels could also be a comma-joined UI value.
        let names = references.flatMap {
            $0.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        if allowAny && names.count == 1 && names[0].lowercased() == "любая" {
            return CivilizationCatalog.standard.map(\.id)
        }
        return try names.map { name in
            guard let civilization = CivilizationCatalog.resolve(name) else {
                throw LibraryError.invalidDocument("\(context): неизвестная цивилизация «\(name)».")
            }
            return civilization.id
        }
    }

    private static func normalizeLegacy(_ build: BuildOrder) throws -> BuildOrder {
        let civilizations = try legacyIDs(build.civilizations,
                                         context: "Билд «\(build.id)»", allowAny: true)
        let steps = try build.steps.enumerated().map { (index, step) -> BuildStep in
            let context = "Билд «\(build.id)», шаг \(index + 1)"
            let include = try step.includeOnly.map { try legacyIDs($0, context: context + " includeOnly") }
            let exclude = try step.exclude.map { try legacyIDs($0, context: context + " exclude") }
            return BuildStep(action: step.action, targetVillagers: step.targetVillagers,
                             targetTimeSeconds: step.targetTimeSeconds, allocation: step.allocation,
                             note: step.note, unitGoals: step.unitGoals,
                             includeOnly: include, exclude: exclude,
                             technologyGoals: step.technologyGoals)
        }
        return BuildOrder(id: build.id, name: build.name, civilizations: civilizations,
                          map: build.map, mapScriptFile: build.mapScriptFile,
                          strategy: build.strategy, description: build.description,
                          steps: steps, sources: build.sources, planStatus: build.planStatus,
                          strategyFamily: build.strategyFamily, startingFoodRequirements: build.startingFoodRequirements)
    }

    static func bundled() throws -> [BuildOrder] {
        guard let url = TrainerResources.bundle?.url(forResource: "builds", withExtension: "json") else {
            throw LibraryError.invalidDocument("В приложении отсутствует встроенный каталог builds.json.")
        }
        return try decode(Data(contentsOf: url))
    }

    static func merged(bundled: [BuildOrder], custom: [BuildOrder]) -> [BuildOrder] {
        var result = bundled
        for build in custom {
            if let index = result.firstIndex(where: { $0.id == build.id }) {
                result[index] = build
            } else {
                result.append(build)
            }
        }
        return result
    }

    /// Custom builds override packaged IDs and can be reloaded without rebuilding the app.
    static func loadAll() throws -> [BuildOrder] {
        try loadAll(customURL: customBuildsURL, bundled: bundled())
    }

    /// Explicit paths allow safe tests without touching the user's real library.
    static func loadAll(customURL: URL, bundled base: [BuildOrder]) throws -> [BuildOrder] {
        guard FileManager.default.fileExists(atPath: customURL.path) else { return base }
        let data = try Data(contentsOf: customURL)
        let document = try parse(data, allowEmpty: true)
        return merged(bundled: base, custom: document.builds)
    }

    static func prepareCustomBuildsFile() throws -> URL {
        try prepareCustomBuildsFile(at: customBuildsURL)
    }

    static func prepareCustomBuildsFile(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            let template = BuildOrderDocument(schemaVersion: 2,
                                              civilizations: CivilizationCatalog.standard,
                                              builds: [])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(template)
            data.append(0x0A)
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    enum LibraryError: LocalizedError {
        case emptyBuild
        case duplicateID
        case invalidGoal
        case invalidDocument(String)

        var errorDescription: String? {
            switch self {
            case .emptyBuild:
                return "Каждый билд должен содержать хотя бы один шаг."
            case .duplicateID:
                return "В JSON встречаются повторяющиеся идентификаторы билдов."
            case .invalidGoal:
                return "Некорректная цель или тайминг: проверь количества, objectId, порядок targetTimeSeconds и число шагов (максимум 200)."
            case .invalidDocument(let message):
                return message
            }
        }
    }
}
