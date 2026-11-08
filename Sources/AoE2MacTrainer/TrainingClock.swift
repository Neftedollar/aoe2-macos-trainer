import Foundation

/// An estimated game clock. AoE2 ranked/Normal uses 1.7 game seconds per real second.
/// It cannot detect in-game pauses or changes to the game speed.
struct TrainingClock {
    var gameSpeed: Double = 1.7

    private(set) var accumulatedRealSeconds: TimeInterval = 0
    private(set) var resumedAt: Date?

    var isRunning: Bool { resumedAt != nil }

    mutating func toggle(at date: Date = Date()) {
        if let resumedAt {
            accumulatedRealSeconds += max(0, date.timeIntervalSince(resumedAt))
            self.resumedAt = nil
        } else {
            resumedAt = date
        }
    }

    mutating func reset(at date: Date = Date()) {
        accumulatedRealSeconds = 0
        resumedAt = isRunning ? date : nil
    }

    func seconds(at date: Date = Date()) -> Int {
        let running = resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return max(0, Int((accumulatedRealSeconds + running) * gameSpeed))
    }
}
