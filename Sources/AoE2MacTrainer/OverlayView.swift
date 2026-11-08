import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: TrainerState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AOE2 TRAINER", systemImage: "graduationcap.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Spacer()
                Text((state.isClockFromOCR ? "◉ " : "≈ ") + state.formattedTime)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            if let build = state.selectedBuild {
                VStack(alignment: .leading, spacing: 4) {
                    Text(build.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(build.civilization) · \(build.map) · \(build.strategy)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Divider().overlay(.white.opacity(0.15))

                if let step = state.selectedStep {
                    HStack(alignment: .firstTextBaseline) {
                        Text("ШАГ \(state.stepIndex + 1) / \(build.steps.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                        Spacer()
                        if let delay = state.stepDelaySeconds, state.displayGameSeconds > 0 {
                            Text(delay >= 0 ? "+\(delay) c" : "\(delay) c")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(delay > 10 ? Color.red : Color.green)
                        }
                    }

                    Text(step.action)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if let allocation = step.allocation {
                        HStack(spacing: 12) {
                            Text("Е \(allocation.food)")
                            Text("Д \(allocation.wood)")
                            Text("З \(allocation.gold)")
                            Text("К \(allocation.stone)")
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    if let villagers = step.targetVillagers {
                        if let observed = state.liveHUD?.value(.villagers) {
                            let delta = observed - villagers
                            Text("Крестьяне: \(observed) / \(villagers) к шагу  (\(delta >= 0 ? "+" : "")\(delta))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(delta >= 0 ? .green : .orange)
                        } else {
                            Text("Ориентир: \(villagers) крестьян")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    if let note = step.note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
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
                Text("Не удалось загрузить билд-ордеры")
                    .foregroundStyle(.white)
            }

            if let hud = state.liveHUD, HUDField.resources.contains(where: { hud.value($0) != nil }) {
                Divider().overlay(.white.opacity(0.15))
                Text("ЗАПАСЫ · Δ/ИГР. МИН (не добыча)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                HStack(spacing: 12) {
                    ForEach(HUDField.resources) { resource in
                        if let stock = hud.value(resource) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resource.title)
                                    .foregroundStyle(.white.opacity(0.6))
                                Text("\(stock)")
                                    .foregroundStyle(.white)
                                if let rate = state.netResourceRate(resource) {
                                    Text("\(rate >= 0 ? "+" : "")\(rate)/м")
                                        .foregroundColor(rate < 0 ? .orange : .green)
                                } else {
                                    Text("…/м")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                    }
                }
            }

            Divider().overlay(.white.opacity(0.15))
            Text("⌃⌥N следующий · ⌃⌥P назад · ⌃⌥B билд · ⌃⌥S таймер")
                .font(.system(size: 10))
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
}
