import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: TrainerState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AOE2 TRAINER", systemImage: "graduationcap.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Spacer()
                if state.clockRunning || state.gameSeconds > 0 {
                    Text("Таймер ≈ " + state.formattedTime)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(state.connectionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(state.match == nil ? Color.white.opacity(0.65) : Color.green)
                if state.match == nil, let civilization = state.previewCivilization {
                    Text("\(civilization.name) · \(PreviewText.builds(state.builds.count))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
                if !foodSummary.isEmpty {
                    Text("Для плана · " + foodSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            if let message = state.loadErrorMessage {
                Text(state.catalog.isEmpty
                     ? "Каталог не загружен: \(message)"
                     : "Ошибка обновления JSON. Показана последняя валидная версия.")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            if let notice = state.selectionNotice {
                Text(notice)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let build = state.selectedBuild {
                VStack(alignment: .leading, spacing: 4) {
                    Text("БИЛД \(state.selectedBuildIndex + 1) / \(state.builds.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text(build.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(build.map) · \(build.strategy)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                    if let family = build.strategyFamily {
                        Text("Семейство: \(family)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    if let requirements = build.startingFoodRequirements, !requirements.isEmpty {
                        Text("Условия варианта: " + foodRequirements(requirements))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                    if let status = build.planStatus, !status.isEmpty {
                        Text("Статус плана: \(status)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                    }
                }

                Divider().overlay(.white.opacity(0.15))

                if let step = state.selectedStep {
                    HStack(alignment: .firstTextBaseline) {
                        Text("ШАГ \(state.stepIndex + 1) / \(build.steps.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                        Spacer()
                        if let delay = state.stepDelaySeconds, state.gameSeconds > 0 {
                            Text(delay >= 0 ? "≈ +\(delay) c" : "≈ \(delay) c")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(delay > 10 ? Color.red : Color.green)
                        }
                    }

                    Text(step.action)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if let deadline = step.targetTimeSeconds {
                        Text("Цель к \(String(format: "%02d:%02d", deadline / 60, deadline % 60)) игры")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if let allocation = step.allocation {
                        HStack(spacing: 9) {
                            Text("Цель:")
                            Text("Е \(allocation.food)")
                            Text("Д \(allocation.wood)")
                            Text("З \(allocation.gold)")
                            Text("К \(allocation.stone)")
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    if let villagers = step.targetVillagers {
                        Text("Ориентир · \(PreviewText.villagers(villagers))")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    if let unitGoals = step.unitGoals {
                        ForEach(unitGoals, id: \.objectId) { goal in
                            Text("Цель: \(goal.label) ×\(goal.count) · ID \(goal.objectId)")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    if let technologyGoals = step.technologyGoals {
                        ForEach(technologyGoals, id: \.technologyId) { goal in
                            Text("Цель: изучено \(goal.label)")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    if let note = step.note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                    }

                    ProgressView(value: Double(state.stepIndex + 1), total: Double(build.steps.count))
                        .tint(.orange)

                    if let next = state.nextStep {
                        Text("ДАЛЬШЕ  " + next.action)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                }
            } else {
                Text(unavailablePlanMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(.white.opacity(0.15))
            VStack(alignment: .leading, spacing: 3) {
                Text("⌃⌥N далее · ⌃⌥P назад · ⌃⌥B билд · ⌃⌥S таймер")
                Text("Шаги и таймер тренировки переключаются вручную. Таймер 1,7×.")
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.48))
        }
        .padding(16)
        .frame(width: 350, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(red: 0.07, green: 0.09, blue: 0.12).opacity(0.91))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                )
        )
        .preferredColorScheme(.dark)
    }

    private var foodSummary: String {
        StartingFoodKind.allCases.compactMap { kind in
            let count = state.previewFoodEvidence.observedCount(for: kind)
            return count > 0 ? "\(kind.displayName) · \(count)" : nil
        }.joined(separator: "   ")
    }

    private func foodRequirements(_ requirements: [StartingFoodRequirement]) -> String {
        requirements.map { requirement in
            "\(requirement.kind.displayName) ≥ \(requirement.minCount)"
        }.joined(separator: " · ")
    }

    private var unavailablePlanMessage: String {
        guard state.previewCivilizationID != nil else {
            return state.match == nil
                ? "Открой записываемую партию или выбери цивилизацию в меню 🏰 для предпросмотра."
                : "Без подтверждённой цивилизации подбор билдов недоступен."
        }
        if let requested = state.requestedBuildID {
            let title = state.unavailableRequestedBuild?.name ?? requested
            return "«\(title)» сейчас недоступен. Проверь выбранную цивилизацию и дичь на старте или выбери другой билд в меню 🏰."
        }
        if state.builds.isEmpty {
            return "Для выбранной цивилизации и дичи подходящих билдов нет."
        }
        return "Выбери билд в меню 🏰 → «Подходящие билды» или нажми ⌃⌥B."
    }
}
