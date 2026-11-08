import Combine
import Foundation

@MainActor
final class TrainerState: ObservableObject {
    @Published private(set) var builds: [BuildOrder]
    @Published private(set) var selectedBuildIndex = 0
    @Published private(set) var stepIndex = 0
    @Published private(set) var gameSeconds = 0
    @Published private(set) var clockRunning = false
    @Published private(set) var hud: HUDSnapshot?

    private var clock = TrainingClock()
    private var resourceTrends = ResourceTrends()

    init(builds: [BuildOrder] = BuildOrderLibrary.bundled()) {
        self.builds = builds
    }

    var selectedBuild: BuildOrder? {
        builds.indices.contains(selectedBuildIndex) ? builds[selectedBuildIndex] : nil
    }

    var selectedStep: BuildStep? {
        guard let selectedBuild, selectedBuild.steps.indices.contains(stepIndex) else { return nil }
        return selectedBuild.steps[stepIndex]
    }

    var nextStep: BuildStep? {
        guard let selectedBuild, selectedBuild.steps.indices.contains(stepIndex + 1) else { return nil }
        return selectedBuild.steps[stepIndex + 1]
    }

    func next() {
        guard let selectedBuild else { return }
        stepIndex = min(stepIndex + 1, selectedBuild.steps.count - 1)
    }

    func previous() {
        stepIndex = max(0, stepIndex - 1)
    }

    func selectBuild(_ index: Int) {
        guard builds.indices.contains(index) else { return }
        selectedBuildIndex = index
        stepIndex = 0
    }

    func cycleBuild() {
        guard !builds.isEmpty else { return }
        selectBuild((selectedBuildIndex + 1) % builds.count)
    }

    func toggleClock() {
        clock.toggle()
        clockRunning = clock.isRunning
        tick()
    }

    func reset() {
        stepIndex = 0
        clock.reset()
        resourceTrends = ResourceTrends()
        tick()
    }

    func tick() {
        let seconds = clock.seconds()
        if seconds != gameSeconds { gameSeconds = seconds }
    }

    func recordHUD(_ snapshot: HUDSnapshot?) {
        guard hud?.capturedAt != snapshot?.capturedAt else { return }
        hud = snapshot
        if let snapshot { resourceTrends.add(snapshot) }
    }

    var liveHUD: HUDSnapshot? {
        guard let hud, Date().timeIntervalSince(hud.capturedAt) < 7 else { return nil }
        return hud
    }

    var displayGameSeconds: Int {
        liveHUD?.value(.clock) ?? gameSeconds
    }

    var isClockFromOCR: Bool {
        liveHUD?.value(.clock) != nil
    }

    func netResourceRate(_ resource: HUDField) -> Int? {
        guard liveHUD?.value(resource) != nil else { return nil }
        return resourceTrends.netPerGameMinute(for: resource)
    }

    var formattedTime: String {
        String(format: "%02d:%02d", displayGameSeconds / 60, displayGameSeconds % 60)
    }

    /// Positive means the estimated game clock is later than the reference step.
    var stepDelaySeconds: Int? {
        guard let target = selectedStep?.targetTimeSeconds else { return nil }
        return displayGameSeconds - target
    }
}
