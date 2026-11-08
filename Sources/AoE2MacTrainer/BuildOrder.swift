import Foundation

struct ResourceAllocation: Codable, Equatable {
    let food: Int
    let wood: Int
    let gold: Int
    let stone: Int

    var isValid: Bool { [food, wood, gold, stone].allSatisfy { $0 >= 0 } }
}

/// A minimum number of currently owned objects of a specific AoE2 object ID.
/// Buildings and units share the same IDs in the XS API.
struct UnitGoal: Codable, Equatable {
    let objectId: Int
    let count: Int
    let label: String

    var isValid: Bool { objectId > 0 && count > 0 && !label.isEmpty }
}

struct BuildStep: Codable, Equatable {
    let action: String
    let targetVillagers: Int?
    let targetTimeSeconds: Int?
    let allocation: ResourceAllocation?
    let note: String?
    let unitGoals: [UnitGoal]?

    init(
        action: String,
        targetVillagers: Int? = nil,
        targetTimeSeconds: Int? = nil,
        allocation: ResourceAllocation? = nil,
        note: String? = nil,
        unitGoals: [UnitGoal]? = nil
    ) {
        self.action = action
        self.targetVillagers = targetVillagers
        self.targetTimeSeconds = targetTimeSeconds
        self.allocation = allocation
        self.note = note
        self.unitGoals = unitGoals
    }

    var isValid: Bool {
        !action.isEmpty && (targetVillagers ?? 0) >= 0 && (targetTimeSeconds ?? 0) >= 0 &&
            (allocation?.isValid ?? true) &&
            (unitGoals?.count ?? 0) <= 8 &&
            (unitGoals?.allSatisfy(\.isValid) ?? true) &&
            Set((unitGoals ?? []).map(\.objectId)).count == (unitGoals?.count ?? 0)
    }
}

struct BuildOrder: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let civilization: String
    let map: String
    let strategy: String
    let description: String
    let steps: [BuildStep]

    var hasValidGoalsAndTimeline: Bool {
        guard !steps.isEmpty, steps.count <= 200, steps.allSatisfy(\.isValid) else { return false }
        var lastDeadline = -1
        for step in steps {
            if let time = step.targetTimeSeconds {
                if time < lastDeadline { return false }
                lastDeadline = time
            }
        }
        return true
    }
}

enum BuildOrderLibrary {
    static var customBuildsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AoE2MacTrainer", isDirectory: true)
            .appendingPathComponent("builds.json")
    }

    static func decode(_ data: Data) throws -> [BuildOrder] {
        let builds = try JSONDecoder().decode([BuildOrder].self, from: data)
        guard !builds.isEmpty, builds.allSatisfy({ !$0.steps.isEmpty }) else {
            throw LibraryError.emptyBuild
        }
        guard builds.allSatisfy(\.hasValidGoalsAndTimeline) else {
            throw LibraryError.invalidGoal
        }
        guard Set(builds.map(\.id)).count == builds.count else {
            throw LibraryError.duplicateID
        }
        return builds
    }

    static func bundled() -> [BuildOrder] {
        guard let url = Bundle.module.url(forResource: "builds", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let builds = try? decode(data) else {
            assertionFailure("Missing or invalid builds.json")
            return []
        }
        return builds
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
        let base = bundled()
        guard FileManager.default.fileExists(atPath: customBuildsURL.path) else { return base }
        let data = try Data(contentsOf: customBuildsURL)
        let custom = try JSONDecoder().decode([BuildOrder].self, from: data)
        if custom.isEmpty { return base }
        let validated = try decode(data)
        return merged(bundled: base, custom: validated)
    }

    static func prepareCustomBuildsFile() throws -> URL {
        let url = customBuildsURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            try "[]\n".write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    enum LibraryError: LocalizedError {
        case emptyBuild
        case duplicateID
        case invalidGoal

        var errorDescription: String? {
            switch self {
            case .emptyBuild:
                return "Каждый билд должен содержать хотя бы один шаг."
            case .duplicateID:
                return "В JSON встречаются повторяющиеся идентификаторы билдов."
            case .invalidGoal:
                return "Некорректная цель или тайминг: проверь количества, objectId, порядок targetTimeSeconds и число шагов (максимум 200)."
            }
        }
    }
}
