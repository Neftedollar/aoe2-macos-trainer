import Combine
import Foundation

@MainActor
final class TrainerState: ObservableObject {
    /// Original validated definitions, including all civilization/step selectors.
    /// Export the catalog, never the resolved preview below.
    @Published private(set) var catalog: [BuildOrder] = []
    @Published private(set) var builds: [BuildOrder] = []
    @Published private(set) var previewCivilizationID: String? = nil
    /// These are manually supplied preview assumptions, never live observations.
    @Published private(set) var previewFoodEvidence: StartingFoodEvidence = .unknown
    @Published private(set) var requestedBuildID: String? = nil
    @Published private(set) var requestedStrategyFamily: String? = nil
    /// A same-family fallback is permitted only after an incompatible civ or
    /// catalog removal, and must be visible instead of silently changing plans.
    @Published private(set) var selectionNotice: String? = nil
    @Published private(set) var loadErrorMessage: String? = nil
    /// -1 means no selected plan, even when other eligible plans are available.
    @Published private(set) var selectedBuildIndex = -1
    @Published private(set) var stepIndex = 0
    @Published private(set) var gameSeconds = 0
    @Published private(set) var clockRunning = false

    private var clock = TrainingClock()
    private let catalogLoader: () throws -> [BuildOrder]
    /// Preserve progress while a manually edited food assumption temporarily
    /// makes the requested variant unavailable. Explicit navigation resets it.
    private var requestedStepIndex = 0

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
            let eligible = BuildOrderLibrary.eligible(
                replacement, civilizationID: previewCivilizationID,
                startingFoodEvidence: previewFoodEvidence
            )
            // Commit only after the whole replacement is loaded and validated.
            catalog = replacement
            selectionNotice = nil
            applyEligible(eligible, allowInitialChoice: false,
                          allowFamilyFallback: true, restoreStep: false)
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
        previewCivilizationID = nextID
        selectionNotice = nil
        if nextID == nil {
            requestedBuildID = nil
            requestedStrategyFamily = nil
            requestedStepIndex = 0
        }
        applyEligible(BuildOrderLibrary.eligible(catalog, civilizationID: nextID,
                                                startingFoodEvidence: previewFoodEvidence),
                      allowInitialChoice: true, allowFamilyFallback: true, restoreStep: false)
    }

    /// Replaces manual PREVIEW assumptions. Real same-match observations belong
    /// to XS and use cumulative evidence; this app has no connection to them.
    func updatePreviewFoodEvidence(_ evidence: StartingFoodEvidence) {
        let bounded = StartingFoodEvidence(pushableHuntCount: min(32, evidence.pushableHuntCount),
                                           smallGameCount: min(32, evidence.smallGameCount))
        guard bounded != previewFoodEvidence else { return }
        previewFoodEvidence = bounded
        applyEligible(BuildOrderLibrary.eligible(catalog, civilizationID: previewCivilizationID,
                                                startingFoodEvidence: bounded),
                      allowInitialChoice: false, allowFamilyFallback: false, restoreStep: true)
    }

    private func applyEligible(_ eligible: [BuildOrder], allowInitialChoice: Bool,
                               allowFamilyFallback: Bool, restoreStep: Bool) {
        let preferredIndex = requestedBuildID.flatMap { id in
            eligible.firstIndex { $0.id == id }
        }
        let requestedDefinition = requestedBuildID.flatMap { id in
            catalog.first { $0.id == id }
        }
        let requestedSupportsCiv = previewCivilizationID.map { civilizationID in
            requestedDefinition?.supports(civilizationID: civilizationID) ?? false
        } ?? false
        // Missing food observations are NOT a reason to replace the user's
        // selected variant. Keep it pending even when a generic sibling exists.
        let canFallBack = allowFamilyFallback && requestedBuildID != nil && !requestedSupportsCiv
        let familyIndex: Int? = canFallBack ? requestedStrategyFamily.flatMap { family in
            eligible.firstIndex { ($0.strategyFamily ?? $0.id) == family }
        } : nil
        let initialIndex: Int? = allowInitialChoice && requestedBuildID == nil && !eligible.isEmpty ? 0 : nil
        builds = eligible
        if let index = preferredIndex ?? familyIndex ?? initialIndex {
            let isFamilyFallback = preferredIndex == nil && familyIndex == index
            let previousTitle = requestedDefinition?.name ?? requestedBuildID ?? ""
            let step = restoreStep && preferredIndex == index ? requestedStepIndex : 0
            activateBuild(at: index, step: step)
            if isFamilyFallback {
                let reason = requestedDefinition == nil
                    ? "больше нет в каталоге"
                    : "не подходит выбранной цивилизации"
                selectionNotice = "«\(previousTitle)» \(reason). Выбран «\(builds[index].name)» того же семейства."
            }
        } else {
            selectedBuildIndex = -1
            stepIndex = 0
            selectionNotice = nil
            if !restoreStep { requestedStepIndex = 0 }
        }
    }

    private func activateBuild(at index: Int, step: Int) {
        let build = builds[index]
        selectedBuildIndex = index
        requestedBuildID = build.id
        requestedStrategyFamily = build.strategyFamily ?? build.id
        stepIndex = min(max(0, step), max(0, build.steps.count - 1))
        requestedStepIndex = stepIndex
    }

    var unavailableRequestedBuild: BuildOrder? {
        guard selectedBuild == nil, let requestedBuildID else { return nil }
        return catalog.first { $0.id == requestedBuildID }
    }

    /// Export intent only. Never export manually supplied food counts or the
    /// narrowed preview catalog; the XS runtime must establish its own facts.
    var exportPreferredBuildID: String? {
        guard let requestedBuildID else { return nil }
        return catalog.contains { $0.id == requestedBuildID } ? requestedBuildID : nil
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
        requestedStepIndex = stepIndex
    }

    func previous() {
        guard selectedBuild != nil else { return }
        stepIndex = max(0, stepIndex - 1)
        requestedStepIndex = stepIndex
    }

    func selectBuild(_ index: Int) {
        guard builds.indices.contains(index) else { return }
        selectionNotice = nil
        activateBuild(at: index, step: 0)
    }

    func cycleBuild() {
        guard !builds.isEmpty else { return }
        let nextIndex = builds.indices.contains(selectedBuildIndex)
            ? (selectedBuildIndex + 1) % builds.count : 0
        selectBuild(nextIndex)
    }

    func toggleClock() {
        clock.toggle()
        clockRunning = clock.isRunning
        tick()
    }

    func reset() {
        stepIndex = 0
        requestedStepIndex = 0
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
