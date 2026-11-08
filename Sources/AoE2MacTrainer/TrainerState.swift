import Combine
import Foundation

@MainActor
final class TrainerState: ObservableObject {
    /// Original validated definitions, including all civilization/step selectors.
    /// Export the catalog, never the resolved preview below.
    @Published private(set) var catalog: [BuildOrder] = []
    @Published private(set) var builds: [BuildOrder] = []
    @Published private(set) var previewCivilizationID: String? = nil
    @Published private(set) var loadErrorMessage: String? = nil
    @Published private(set) var selectedBuildIndex = 0
    @Published private(set) var stepIndex = 0
    @Published private(set) var gameSeconds = 0
    @Published private(set) var clockRunning = false

    private var clock = TrainingClock()
    private let catalogLoader: () throws -> [BuildOrder]

    /// The optional injected catalog/loader make preview and atomic reload
    /// behavior testable without changing a user's application-support files.
    init(builds: [BuildOrder]? = nil,
         loader: @escaping () throws -> [BuildOrder] = { try BuildOrderLibrary.loadAll() }) {
        catalogLoader = loader
        do {
            let initial: [BuildOrder]
            if let builds {
                initial = builds
            } else {
                initial = try loader()
            }
            try BuildOrderLibrary.validate(initial)
            catalog = initial
        } catch {
            // An invalid custom JSON must not silently look like a successful
            // load of the bundled catalog. Start disconnected and report it.
            loadErrorMessage = error.localizedDescription
        }
    }

    func reloadBuilds() throws {
        do {
            let replacement = try catalogLoader()
            try BuildOrderLibrary.validate(replacement)
            let preferredID = selectedBuild?.id
            let eligible = BuildOrderLibrary.eligible(
                replacement, civilizationID: previewCivilizationID
            )
            // Commit only after the whole replacement is loaded and validated.
            catalog = replacement
            applyEligible(eligible, preferredID: preferredID)
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = error.localizedDescription
            throw error
        }
    }

    var previewCivilization: CivilizationDefinition? {
        previewCivilizationID.flatMap(CivilizationCatalog.resolve)
    }

    /// Explicitly manual. This does not set or claim to detect the game's civ.
    func selectPreviewCivilization(_ rawID: String?) {
        let nextID = rawID.flatMap(CivilizationCatalog.resolve)?.id
        guard nextID != previewCivilizationID else { return }
        let preferredID = selectedBuild?.id
        previewCivilizationID = nextID
        applyEligible(BuildOrderLibrary.eligible(catalog, civilizationID: nextID),
                      preferredID: preferredID)
    }

    private func applyEligible(_ eligible: [BuildOrder], preferredID: String?) {
        builds = eligible
        selectedBuildIndex = preferredID.flatMap { id in
            eligible.firstIndex { $0.id == id }
        } ?? 0
        stepIndex = 0
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
        guard let selectedBuild, !selectedBuild.steps.isEmpty else { return }
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
        tick()
    }

    func tick() {
        let seconds = clock.seconds()
        if seconds != gameSeconds { gameSeconds = seconds }
    }

    var formattedTime: String {
        String(format: "%02d:%02d", gameSeconds / 60, gameSeconds % 60)
    }

    /// Positive means the estimated game clock is later than the reference step.
    var stepDelaySeconds: Int? {
        guard let target = selectedStep?.targetTimeSeconds else { return nil }
        return gameSeconds - target
    }
}
