import Foundation

enum HUDField: String, CaseIterable, Codable, Hashable, Identifiable {
    case clock
    case villagers
    case food
    case wood
    case gold
    case stone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: "Время"
        case .villagers: "Крестьяне"
        case .food: "Еда"
        case .wood: "Дерево"
        case .gold: "Золото"
        case .stone: "Камень"
        }
    }

    static let resources: [HUDField] = [.food, .wood, .gold, .stone]
}

/// Rectangles have a top-left origin and are normalized to the full screenshot.
struct NormalizedHUDRect: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var isValid: Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0 &&
        x + width <= 1.001 && y + height <= 1.001
    }
}

struct HUDLayout: Codable, Equatable {
    var regions: [HUDField: NormalizedHUDRect] = [:]

    var hasRegions: Bool { regions.values.contains(where: \.isValid) }

    static func load() -> HUDLayout {
        guard let data = UserDefaults.standard.data(forKey: "HUDLayout.v1"),
              let layout = try? JSONDecoder().decode(HUDLayout.self, from: data) else {
            return HUDLayout()
        }
        return layout
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "HUDLayout.v1")
    }
}

struct HUDSnapshot: Equatable {
    let capturedAt: Date
    let values: [HUDField: Int]

    func value(_ field: HUDField) -> Int? { values[field] }
}

/// Recognized resource values are stockpiles, NOT gross gathering totals.
/// Spending, market trading, and tributes can make these rates negative.
struct ResourceTrends {
    private(set) var samples: [HUDSnapshot] = []

    mutating func add(_ sample: HUDSnapshot) {
        if let previous = samples.last, sample.capturedAt <= previous.capturedAt { return }
        samples.append(sample)
        let cutoff = sample.capturedAt.addingTimeInterval(-75)
        samples.removeAll { $0.capturedAt < cutoff }
    }

    func netPerGameMinute(for resource: HUDField) -> Int? {
        guard HUDField.resources.contains(resource),
              let latest = samples.last,
              let latestAmount = latest.value(resource),
              let earliest = samples.first(where: {
                  $0.value(resource) != nil &&
                  latest.capturedAt.timeIntervalSince($0.capturedAt) >= 12
              }),
              let startingAmount = earliest.value(resource) else { return nil }

        // Normal AoE2 speed: 1 real second is 1.7 in-game seconds.
        let elapsed = latest.capturedAt.timeIntervalSince(earliest.capturedAt) * 1.7
        return Int((Double(latestAmount - startingAmount) * 60 / elapsed).rounded())
    }
}
