import Foundation

/// Categories of observed opening food, not exclusive map profiles. Small game
/// and pushable hunt can coexist. Species classification belongs to the game
/// observer, not to user-authored build requirements.
enum StartingFoodKind: String, Codable, CaseIterable, Hashable {
    case pushableHunt = "pushable-hunt"
    case smallGame = "small-game"
}

struct StartingFoodRequirement: Codable, Equatable {
    let kind: StartingFoodKind
    let minCount: Int

    var isValid: Bool { (1...32).contains(minCount) }
}

/// Confirmed cumulative observations for ONE match. Zero means "none observed",
/// never "none exists". Counts must already be deduplicated by the observer.
/// They say nothing about accessibility, safe pushing, or the player's intent.
struct StartingFoodEvidence: Equatable {
    let pushableHuntCount: Int
    let smallGameCount: Int

    static let unknown = StartingFoodEvidence()

    init(pushableHuntCount: Int = 0, smallGameCount: Int = 0) {
        self.pushableHuntCount = max(0, pushableHuntCount)
        self.smallGameCount = max(0, smallGameCount)
    }

    func observedCount(for kind: StartingFoodKind) -> Int {
        switch kind {
        case .pushableHunt: return pushableHuntCount
        case .smallGame: return smallGameCount
        }
    }

    /// Positive AND only: missing evidence cannot satisfy a requirement.
    /// A plan with no requirements is the generic, food-independent variant.
    func satisfies(requirements: [StartingFoodRequirement]) -> Bool {
        Set(requirements.map(\.kind)).count == requirements.count &&
            requirements.allSatisfy { $0.isValid && observedCount(for: $0.kind) >= $0.minCount }
    }

    /// Merge cumulative snapshots from the SAME match. Never sum repeated
    /// observations or erase evidence because the animals were consumed.
    /// A new match must use a new value, starting at `.unknown`.
    func merging(_ newer: StartingFoodEvidence) -> StartingFoodEvidence {
        StartingFoodEvidence(pushableHuntCount: max(pushableHuntCount, newer.pushableHuntCount),
                             smallGameCount: max(smallGameCount, newer.smallGameCount))
    }
}
