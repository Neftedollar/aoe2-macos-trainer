# AoE2 Mac Trainer

A native macOS companion and **XS training module** for Age of Empires II: Definitive Edition. Public, MIT-licensed, experimental. No OCR, screen capture, process-memory access, or automatic game orders.

Download the app for Apple Silicon from the [v0.7.0 release](https://github.com/Neftedollar/aoe2-macos-trainer/releases/tag/v0.7.0). Open it before or during a recorded Feral match. The 🏰 menu and floating panel pick up your civilization automatically.

## What works in each part

| Component | Implemented behavior | Important limitation |
| --- | --- | --- |
| Generated XS module | Reads the actual local player's civilization and game clock; observes visible nearby starting hunt; filters a complete build catalog; observes goals and rolling economy metrics; displays the current build inside the game | Requires a custom RMS/scenario that loads it; native Mac gameplay has not yet been tested |
| macOS floating overlay | Detects an active Feral recording, resolves the local player's civilization, and filters the training plans. Manual preview is available between matches. | The training timer, food choices and step controls belong to the desktop panel. In-game XS metrics stay in the game. |
| JSON build catalog | Versioned declarations, civilization allowlists, conditional steps, positive food requirements, strategy families, timed goals, source metadata | A valid document is not proof that its timings are achievable in a match |

The current library contains **15 training plans**. The original nine reviewed plans cover 27 explicitly listed civilizations, including Scouts, Archers, Men-at-Arms → Archers, Fast Castle, Turkish Fast Imperial, and Khitan/Armenian/Georgian practice variants. Two additional shared **FC/FI age-training plans cover all 56 registered civilizations**, with regional economic exceptions. Four compact food-sensitive FC/FI variants cover six reviewed normal-start civilizations. These are practice targets, **not 56 optimized military builds**. See the [coverage audit](docs/build-coverage-audit.md) for the remaining gaps.

Still unimplemented: a verified live XS ↔ native-app bridge, exact TC idle time, automatic map detection, reliable boar-specific worker assignment, and replay/post-match analytics. **Control+Option+B does not yet change the running game's XS selection.**

## Build the macOS app

Requires macOS 13 or later and Xcode Command Line Tools or Xcode:

```sh
swift test
bash Scripts/build-app.sh
open .build/AoE2MacTrainer.app
```

The app appears as 🏰 in the menu bar. Open the app again in Finder or press Control+Option+H to show the preview. To start with just the menu bar item during a match, run `open -g .build/AoE2MacTrainer.app --args --menu-bar-only`. The transparent overlay passes clicks through to the game. Windowed/borderless mode may be needed if the panel does not appear over a native fullscreen Space. Detection follows the recording that Feral currently has open for writing, including an already-running or paused match. When the game closes that recording, the app returns to preview. The active recorder's civilization is read from supported DE headers. In single-player a matching Feral session file can also identify the sole human player. Unsupported or ambiguous player data leaves the civilization unknown. For games with recording disabled, use the manual preview.

## Create a training mod

1. Optionally edit the custom JSON through **Открыть пользовательский JSON…** and reload it. An invalid reload reports an error and preserves the previous valid catalog.
2. Choose the local XS-mod creation menu and select **Arena**, **Arabia**, **Nomad**, or an existing `.rms`/`.rms2` that you own. A preview build does not need to be selected. **The entire catalog is exported**, not only the desktop's current filtered list.
3. If exactly one native Feral profile is detected, the app proposes its `mods/local` directory. Otherwise choose that directory manually, or export elsewhere and move the generated folder later. Only new mod folders are created; installed game files and previous mods are never overwritten.
4. Restart AoE2 if needed to refresh its custom-map list. Enable the local mod, then start a custom-map Skirmish against your desired AI difficulty. Select the generated `AoE2Trainer_*` map, **not** the unmodified standard map.
5. XS reads the actual local player and civilization. An eligible preferred build is selected. A civ-compatible food variant waits for positive observations rather than silently becoming another plan. If the preferred build does not support the actual civilization, a same-family alternative may be selected with an explicit fallback notice; it never silently changes FC to FI. With no preferred build, a generic eligible plan is chosen first. No suitable choice remains visibly unavailable.

The native macOS profile location the app checks is:

```text
~/Library/Application Support/Feral Interactive/Age Of Empires II/VFS/User/Games/Age of Empires 2 DE/<steam-id>/mods/local
```

Each mod gets a unique XS filename so enabling two exported catalogs does not silently substitute one module for the other:

```text
AoE2Trainer_Arena/
  info.json
  resources/_common/random-map-scripts/AoE2Trainer_Arena.rms
  resources/_common/xs/aoe2trainer_Arena_<instance>.xs
```

The standard-map wrapper uses:

```text
#includeXS aoe2trainer_Arena_<instance>.xs
#include_drs Arena.rms
```

**The wrapper and this deployment path have not been verified inside the native Mac game.** If the standard-map include is unavailable, package an existing RMS instead. Its custom include dependencies must also be installed. A source RMS already containing `#includeXS` is rejected because combining `main()` functions needs manual integration. Original RMS bytes are preserved apart from the prepended XS include.

Direct catalog export is also available as `aoe2trainer_catalog.xs`. Reference it before `<PLAYER_SETUP>` in your own RMS. The exported module is a **snapshot**: changing JSON later requires another export before a new match.

**Text encoding:** XS source literals are ASCII-only. The current exporter visibly transliterates Russian/other Unicode labels for the in-game XS panel and substitutes readable equivalents for arrows/dashes. Unsupported symbols become explicit `[U+XXXX]` markers, not silently deleted characters. Original JSON and native macOS preview text remain unchanged. A separate localization-resource bundle is not implemented; the export dialog and XS panel disclose this limitation.

### In-game selection versus desktop hotkeys

The generated module contains all eligible plans and exposes these **unbound Scenario Editor Script Call entry points**:

```text
trainerNextBuild()
trainerPreviousBuild()
trainerNextStep()
trainerPreviousStep()
trainerResumeTimeline()
```

Build switching skips ineligible civilizations and unconfirmed food requirements and preserves first-observed goal timestamps. Scouting more food adds choices without replacing an active build or resetting its step. These functions are not keyboard listeners. A scenario can bind them to its own supported triggers; the generated RMS does not yet provide an interactive selector or a live connection to the app's hotkeys. In a plain exported RMS, choose the preferred plan before export.

The game controls the placement of `xsDisplayInstructions`; arbitrary placement immediately below the resource bar is not implemented. Its live panel and the external macOS preview are separate displays.

## JSON v2: shared plans and civilization exceptions

Custom definitions live at `~/Library/Application Support/AoE2MacTrainer/builds.json`. New files use the v2 envelope. The following is a **schema/practice example**, not a verified Fast Imperial opening:

```json
{
  "schemaVersion": 2,
  "civilizations": [
    { "id": "turks", "name": "Турки", "xsID": 10 },
    { "id": "portuguese", "name": "Португальцы", "xsID": 24 }
  ],
  "builds": [
    {
      "id": "my-gunpowder-practice",
      "name": "Учебный Империал → порох",
      "civilizations": ["turks", "portuguese"],
      "map": "Арена",
      "mapScriptFile": "Arena.rms",
      "strategy": "Gunpowder practice",
      "strategyFamily": "fast-imperial",
      "description": "Свободные учебные сроки, не оптимальный билд",
      "planStatus": "practice-targets",
      "steps": [
        {
          "action": "Достичь Имперской эпохи",
          "targetTimeSeconds": 1500,
          "technologyGoals": [{ "technologyId": 103, "label": "Империал" }]
        },
        {
          "action": "Завершить Химию в университете",
          "targetTimeSeconds": 1650,
          "exclude": ["turks"],
          "technologyGoals": [{ "technologyId": 47, "label": "Химия" }]
        },
        {
          "action": "Химия бесплатная: готовить пороховую армию",
          "targetTimeSeconds": 1650,
          "includeOnly": ["turks"]
        }
      ]
    }
  ]
}
```

Rules:

- Root `civilizations` declares canonical IDs and their known XS IDs. Unknown IDs, incorrect XS mappings, and duplicate declarations are errors.
- Each build has a nonempty explicit `civilizations` allowlist. It is an eligibility rule, not a label.
- Optional step `includeOnly` and `exclude` **must be arrays**. Every referenced civilization must be declared and must belong to the parent build. `exclude` wins if both selectors match. An empty `includeOnly` is rejected.
- V2 rejects unknown fields at every object level, so a typo such as `exlclude` cannot silently drop a restriction. Error messages identify the JSON path.
- Validation checks the timeline after resolving each civilization's steps, so mutually exclusive variants may have different times. Every allowed civilization must retain at least one step.
- Unknown/no-current-civilization fails closed. Neither preview nor XS treats that as “show everything.”
- `name` supplies the visible build title. `sources: [{"title": "...", "url": "https://..."}]` and `planStatus` preserve provenance.
- Optional `strategyFamily` is a nonempty lowercase kebab-case ID such as `fast-castle` or `fast-imperial`. It identifies like-for-like alternatives; it does not turn an age-training exercise into an optimized military plan.
- Optional `startingFoodRequirements` is an array of positive requirements. Each `kind` is `pushable-hunt` or `small-game`, with integer `minCount` from 1 through 32 and no duplicate kind. All listed requirements must hold. Omit the field (or use an empty array) for a food-independent plan.
- Custom builds override bundled builds with the same `id`. A valid empty custom catalog adds no overrides. Invalid JSON does not silently fall back or partially load.

Older root-array documents, the singular `civilization` field, and recognized Russian/English aliases are imported for compatibility. Legacy `Любая` expands to the known registry only during legacy import; v2 requires explicit declarations/allowlists. Existing custom files are never rewritten automatically.

### Food-sensitive alternatives

For example, a hunt variant can add the following build-level field while keeping an explicit civilization allowlist:

```json
"startingFoodRequirements": [
  { "kind": "pushable-hunt", "minCount": 3 }
]
```

Use `small-game` for the corresponding wild-chicken/hare variant. These are separate plans with their own instructions, not a blind substitution of one animal name for another. The current four sample variants support Portuguese, Turks, Spanish, Byzantines, Magyars and Berbers; the two generic FC/FI exercises remain available for the full registry.

XS counts distinct **live animals observed in current local-player visibility**, within 24 tiles of the first own TC, during the first 600 game seconds. Regular deer-type hunt and wild small game use an explicit species whitelist. Herdable chickens and gold-bearing foxes are not mixed into those categories. Repeated sightings are deduplicated by instance ID; past observations remain after consumption. Zero means **not yet observed**, never proof of absence.

The counters are historical observations, **not remaining food, a completed deer push, or a safety/reachability guarantee**. Seeing small game does not prove that deer are absent. Map names, seeds and a generic RMS wrapper do not reveal which local food branch was generated. Unsupported species and scan limits can undercount; incomplete observations are disclosed. See [food detection and its information boundary](docs/food-detection.md).

The menu's food counts are manual preview inputs only and are **never exported as game facts**. They let you inspect conditional variants before a match. The generated XS module observes the actual game independently. A preferred food variant can wait for evidence; choose a generic plan before export if you want an immediately available opening in a plain RMS.

Hunt-first instructions prioritize practical fast food while retaining sheep as a bridge. They must not encourage an idle TC just to minimize sheep consumption. Walking, drop-off, mill cost, scout attention and civilization bonuses all matter.

### Goal semantics

| Field | What it means |
| --- | --- |
| `targetTimeSeconds` | Deadline in **game seconds**, not real seconds; passing it does not complete a goal |
| `targetVillagers` | Minimum current **living villagers**, not population or lifetime production |
| `allocation` | Minimum approximate workers on food/wood/gold/stone; not exact assignment to a particular boar |
| `unitGoals` | Current owned object counts by `objectId`; foundations and upgraded IDs require caution |
| `technologyGoals` | Technology is **completed** (`xsGetTechState(id, player) == 3`), not merely queued or researching |

All measurable conditions in a step must hold together. A MET status confirms those declared conditions, not every imperative in the free-text instruction. The script samples every two game seconds and remembers the first observation satisfying a step. It tracks all civilization-eligible plans, including those not currently displayed, so switching does not invent a new achievement time. Loading the script late cannot reconstruct prior events. Steps without a measurable condition remain **MANUAL ACTION**, not automatically completed instructions.

Upcoming incomplete checkpoints are shown before their deadlines. Late/missed checkpoints remain in a summary; manual next/previous selects an instruction but never marks its goal complete. Goal timing has the sampling resolution of the XS rule, not frame-perfect precision.

An untimed manual step requires explicit next-step navigation. Give instructions deadlines for automatic timeline progression; all bundled plans do this. A plain generated RMS currently has no bound next-step input.

## Economy metrics

The XS panel shows each resource's gross collection per minute over a rolling 60 **game-second** window, average estimated workers over that window, and approximate collection per worker. It reads cumulative collected counters (`166…169`), **not the resource stockpile**, so spending does not masquerade as lower collection. There is a warm-up before a full window is available.

The boundary between samples is interpolated for the cumulative counters. Average workers are time-weighted, retain fractional values, and use the last observed count between samples. A gap longer than six game seconds suppresses rates until a continuous window is available. Rewound time or decreasing counters reset the window; repeated paused instants add no elapsed worker time. These are sampling estimates, not continuous per-frame measurements.

Worker assignment is inferred from unit targets/carried resources. Drop-off, idle/building tasks, special sources such as Khitan pastures, and non-villager income can distort it. These rates are diagnostics, not an exact “efficiency percentage.” Exact TC idle time is not inferred from missing villager growth: research, age advancement, and other TC actions must be distinguished first.

## Build library and review

See [the source and review notes](docs/build-library-sources.md) for all 15 plans, authors, timing assumptions, and civilization exceptions, and the [coverage audit](docs/build-coverage-audit.md) for per-family coverage and remaining military-build gaps. `source-adapted` identifies an adaptation of an authored guide; `practice-targets` identifies deliberately loose exercise targets. **Neither label means match-verified.**

The Khitan plan accounts for pastures and the absence of Knights/Bloodlines. It is an early-game training variant, not a claimed optimized Mounted Trebuchet opening. Population, living villagers, and time spent researching at the TC are kept distinct.

## Hotkeys — desktop preview only

| Keys | Preview action |
| --- | --- |
| Control + Option + N / P | Next / previous effective build step |
| Control + Option + B | Next build eligible for the detected or preview civilization and selected food counts |
| Control + Option + S | Start/pause estimated 1.7× clock |
| Control + Option + R | Reset preview clock and step |
| Control + Option + H | Show/hide overlay |

These actions never issue game commands or change the running XS plan. Accessibility/system shortcuts may conflict. A live hotkey bridge is a remaining milestone, not a completed feature.

## Live bridge investigation and multiplayer limits

Older [XSLC source](https://github.com/prelusion/XSLiveCommands) demonstrates an external file-command design using XS `.xsdat` reads. Its Mac client is unimplemented and it targets an older game version. Separately, [aoe2kit's engine-testing notes](https://github.com/chrae/aoe2kit/blob/main/docs/SIDECAR.md) report buffered XS writes. Therefore live transfer is **not proven impossible**, but neither direction is verified on the current native Mac engine. This project does not yet implement that bridge and has not copied XSLC's GPL-licensed code.

Local XS file input may cause multiplayer desynchronization unless all participants have identical inputs. No multiplayer-safe or ranked/competitive use is claimed. Use explicitly loaded custom single-player training maps until runtime, synchronization, and fair-play requirements are verified. The script does not inspect opponents or alter the simulated world.

## Validation and next steps

GitHub Actions assembles the runtime with its food-observer fragment for an early XS check, builds the app on macOS, runs Swift tests, generates the **actual full-catalog XS**, and checks that artifact with the pinned [XS Check](https://github.com/Divy1211/xs-check) CLI. Grammar/type checks catch errors that string assertions do not. Neither CI nor a successful `.app` build proves the module loads in AoE2 or measures the intended state.

Remaining acceptance checks:

1. Load the generated mod in native macOS AoE2 and verify the actual civ, title, game clock, completed-technology state and no-match behavior.
2. Compare rolling rates and worker estimates with a controlled gathering exercise; verify gaps, restarts and age transitions.
3. Verify hidden, currently visible and explored-but-hidden animals; mixed hunt, repeat sightings, consumption, unknown species and the 24-tile/600-second observation boundaries. New discoveries must not change the chosen plan.
4. Validate in-game build/step selection and a safe external bridge, without OCR or memory access.
5. Calibrate guide-derived and practice timelines in real training games. Defer replay/post-match features.

## References and license

- [Official XS API](https://www.forgottenempires.net/age-of-empires-ii-definitive-edition/xs-scripting-in-age-of-empires-ii-definitive-edition)
- [XS language guide](https://ugc.aoe2.rocks/general/xs/programmer/)
- [XS functions](https://ugc.aoe2.rocks/general/xs/functions/functions/)
- [Resource counters](https://ugc.aoe2.rocks/general/resources/resources/)
- [2026 local-player API rename](https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-185872/)

MIT — see [LICENSE](LICENSE). The recorded-header reader uses the MIT-licensed aoc-mgz layout. Its attribution is included in the source and the app. Third-party guides and videos retain their own licenses.
