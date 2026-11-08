import Foundation

struct ResourceAllocation: Codable, Equatable {
    let food: Int
    let wood: Int
    let gold: Int
    let stone: Int
}

struct BuildStep: Codable, Equatable {
    let action: String
    let targetVillagers: Int?
    let targetTimeSeconds: Int?
    let allocation: ResourceAllocation?
    let note: String?
}

struct BuildOrder: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let civilization: String
    let map: String
    let strategy: String
    let description: String
    let steps: [BuildStep]
}

enum BuildOrderLibrary {
    static func decode(_ data: Data) throws -> [BuildOrder] {
        let builds = try JSONDecoder().decode([BuildOrder].self, from: data)
        guard !builds.isEmpty, builds.allSatisfy({ !$0.steps.isEmpty }) else {
            throw LibraryError.emptyBuild
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

    enum LibraryError: Error {
        case emptyBuild
        case duplicateID
    }
}
