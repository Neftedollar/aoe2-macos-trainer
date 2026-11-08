# AoE2 Mac Trainer

A native macOS training HUD for **Age of Empires II: Definitive Edition**, designed for the official Apple Silicon edition on Steam.

The goal is to help 1v1 players practice unfamiliar civilizations without leaving their match. The overlay floats over the game and lets mouse clicks pass through to AoE2.

## Current status (experimental)

- Native transparent `NSPanel` overlay (SwiftUI + AppKit)
- Click-through window with support for macOS fullscreen Spaces
- Menu-bar controller; no Dock icon
- Global hotkeys for build navigation, build selection, overlay visibility and timer control
- Ten sample builds, including Arabia Scouts/Archers, Arena Fast Castle, Portuguese FC, Spanish Castle Drop, Armenian/Georgian FC, Fast Castle Knights, FC Monks, Fast Imperial, and Amazon Tunnel Boom
- Training timer calibrated to **1.7x** normal AoE2 game speed
- XS script exporter that turns the selected **JSON build** into a self-contained `.xs` trainer
- Custom JSON file in `~/Library/Application Support/AoE2MacTrainer/builds.json`, reloadable from the menu without rebuilding
- JSON `civilizations` array permits multiple applicable civilizations for the same strategy (older `civilization` string files still load)
- Local XS **mod packager**: creates a standalone training map mod with `.rms` and `.xs` files; auto-detects the Feral macOS profile if present and allows choosing a source `.rms` file
- Experimental in-game XS dashboard: actual game time, build steps, villager target, four **gross resource-collected rates** per rolling 60 game seconds
- Approximate number of workers assigned to each resource and per-worker rates, based on the villager task target / cargo
- Time-based XS **checkpoints** with measurable targets for total villagers, workers on each resource and current units/buildings by object ID
- Goal status in-game: due in N seconds, missed deadline, completed early/late, and missed-checkpoint count
- XCTest unit tests and GitHub Actions macOS build

**Not implemented yet:** automatically detecting civilization/map, a verified real-time link from XS to the external macOS overlay, exact TC idle time, identifying villagers on a specific boar reliably, precise per-worker assignment, and post-game replay analysis. The native overlay still uses an **estimated clock** started by hand; the XS instructions use the **actual in-game clock**. All sample build timings remain unverified training placeholders, **not competitive benchmarks**.

## Get started

Requires a Mac with macOS 13 or later and Xcode Command Line Tools or Xcode.

```sh
swift test
bash Scripts/build-app.sh
open .build/AoE2MacTrainer.app
```

The app appears as 🏰 in the macOS menu bar. Launch AoE2 DE in **Windowed/Borderless** mode if the overlay does not appear over native fullscreen. Click-through is enabled permanently; all controls are via the menu-bar icon or global hotkeys.

### XS training module (experimental)

1. Select a build using the 🏰 menu or `Ctrl+Option+B`.
   For custom steps, choose **Открыть пользовательский JSON…**, add your build objects to the `[]` array (using `Resources/builds.json` as the schema), and choose **Перезагрузить JSON-билды**. Custom entries with the same `id` override packaged builds.
2. For an Arena/Arabia/Nomad build, choose **Создать локальный XS-мод…**. This generates a **new** local mod containing both the XS and a custom RMS that tries to include the game's standard map. For a custom map (e.g. Amazon Tunnel), choose **Создать XS-мод из RMS-файла…** and select an existing `.rms` or `.rms2` file that you own.
3. The app discovers macOS Feral profiles under `~/Library/Application Support/Feral Interactive/Age Of Empires II/VFS/User/Games/Age of Empires 2 DE/<steam-id>/mods/local`. If one profile is found, it writes the new mod there. Otherwise select the `mods/local` folder manually, or another export destination and move the result to the actual `mods/local` afterwards. **Only new directories are created; installed game files and previous mods are never overwritten.**
4. Restart AoE2 after generating the mod so its custom-map list can refresh. In AoE2, open **Mods → My Mods / Installed Mods** (the label may vary by version), enable the new local mod if necessary, then start a **Custom Map** match (Skirmish) against the desired AI difficulty. Select the generated `AoE2Trainer_*` map, **not** the unmodified standard map. Once loaded, XS should display the current checkpoint, goal progress, deadlines, resource collection/minute and approximate worker distribution directly in the game. A full 60-game-second window is needed before the first rate appears.

The wrapper RMS for built-in maps contains only:

```text
#includeXS aoe2trainer_YOUR-BUILD.xs
#include_drs Arena.rms
```

The wrapper assumes the game exposes `Arena.rms` through its standard data-archive includes. **This exact macOS deployment and wrapper behavior has not been tested in the game.** If it fails, use the second menu option to package a copy of an existing RMS instead. Third-party RMS scripts that depend on relative custom include files may require those dependencies to be installed as well.

The generated mod layout is:

```text
AoE2Trainer_example/
  info.json
  resources/_common/random-map-scripts/AoE2Trainer_example.rms
  resources/_common/xs/aoe2trainer_example.xs
```

The old **Экспорт XS для выбранного билда…** command is still available if you prefer manual integration into an existing RMS. The XS file must be referenced by `#includeXS` **before** `<PLAYER_SETUP>`.

**Important:** the native XS display is separate from the SwiftUI overlay. The macOS HUD shows the selected JSON `name` prominently and the `civilizations` list, and lets you cycle through builds via `Ctrl+Option+B`; its steps are manually controlled by hotkeys. The **exported XS module is a snapshot** of the build selected when the mod was generated. To change the live XS script's build, generate/select a different training mod before the match. The XS panel follows actual in-game time and is placed by AoE2 at its built-in **top instruction position** (about 13% from the top), not at an arbitrary pixel coordinate. Neither runtime gameplay nor script loading on macOS has been verified yet.

### Timed checkpoints and JSON goals

The custom file is a **JSON array** of build definitions; the full schema is the bundled `Sources/AoE2MacTrainer/Resources/builds.json`.

```json
[
  {
    "id": "my-arabia-goals",
    "name": "My first 10 minutes",
    "civilizations": ["Армяне", "Грузины"],
    "map": "Аравия",
    "mapScriptFile": "Arabia.rms",
    "strategy": "Scouts",
    "description": "Custom training checkpoints",
    "steps": [
      { "action": "6 villagers on food", "targetTimeSeconds": 75, "targetVillagers": 6,
        "allocation": { "food": 6, "wood": 0, "gold": 0, "stone": 0 } },
      { "action": "Reach 20 villagers and build a stable", "targetTimeSeconds": 600,
        "targetVillagers": 20,
        "allocation": { "food": 8, "wood": 7, "gold": 0, "stone": 0 },
        "unitGoals": [{ "objectId": 101, "count": 1, "label": "Stable" }] }
    ]
  }
]
```

`targetTimeSeconds` is **in-game time**, e.g. `600` means 10:00. Targets are minimums, not exact worker allocations: if food target is 6, having 7 qualifies. `targetVillagers` checks currently living villagers. `unitGoals` uses AoE2 object IDs to check the **current count** of owned units/buildings (e.g. `101` stable, `87` archery range, `448` scout cavalry, `4` archer); it does not reliably prove that a building has finished construction or that a given production action was executed. Unit counts can be affected by units dying or upgrades. Object IDs can change with regional units or game modes.

`civilizations` accepts any non-empty list of display names; the app does **not** auto-detect the current civilization yet. Legacy custom JSON with the singular `"civilization": "Португальцы"` continues to work; new JSON may also use a `"civilization"` string array, but `civilizations` is preferred. `mapScriptFile` is optional: it names a built-in `.rms` included with `#include_drs` and can be specified for a custom map if you know its exact game file name. For imported RMS files, use the dedicated menu command. The JSON must contain one or more steps ordered by `targetTimeSeconds`.

The XS rule samples every **2 in-game seconds** and records the first time each measurable goal is seen as achieved. `MET EARLY` / `MET LATE` compares that observation to the deadline; `LATE` means unmet and overdue. `MISSED CHECKPOINTS` summarizes unfinished or late goals. The currently displayed step follows the timeline even if an earlier target was missed. Steps without measurable goals are labelled `MANUAL ACTION` and cannot be automatically verified.

Worker assignment is **approximate**: XS infers it from the villager's current target or carried resource. Therefore `allocation.food` means roughly “villagers working on food”, not “villagers specifically on this boar”. Accurate boar-only targets are **not implemented**. Building, queue and exact TC-idle checks also need more engine-level validation.

The XS script reads **only the local player's** cumulative resource-collected counters (`166..169`) rather than subtracting resource stockpiles: buying units does **not** reduce the measured gathering rate. These counters can also reflect resource generation from non-villager sources; worker counts are estimates based on unit targets and carried materials, and cannot distinguish every builder/returning/idle villager. **Per-worker rates are diagnostic approximations.**

The script does not change the world, create units, issue commands, or inspect opponents. No screen capture, process injection, or keyboard automation is used. **The exported script requires a custom RMS/scenario that loads it.** Ordinary ranked or unmodified 4v4 maps cannot be assumed to load it. Multiplayer rules and parity on the native Mac port remain to be tested.

**Why not use `.xsdat` for live streaming?** Available XS engine-testing documentation indicates that `.xsdat` writes remain buffered until a scenario ends, so the script computes and displays live metrics **inside the game**. The external app cannot honestly claim a live XS data feed yet. This experimental design leaves replay parsing out of scope.

## Hotkeys

| Keys | Action |
| --- | --- |
| Control + Option + N | Next build step |
| Control + Option + P | Previous build step |
| Control + Option + B | Next build order |
| Control + Option + S | Start/pause estimated game clock |
| Control + Option + R | Reset clock and step |
| Control + Option + H | Show/hide overlay |

**Start the clock as the match begins**. Reference timings are in AoE2 game seconds, not wall-clock seconds. macOS accessibility shortcuts may conflict with the default hotkeys; hotkey customization is planned.

## Architecture

| Component | Purpose |
| --- | --- |
| `BuildOrder.swift` | JSON build definitions and validation |
| `TrainingClock.swift` | Pausable estimated AoE2 game clock |
| `TrainerState.swift` | Step navigation, selected build and UI state |
| `OverlayView.swift` | Read-only, click-through SwiftUI HUD |
| `OverlayController.swift` | Floating fullscreen-compatible `NSPanel` |
| `HotkeyManager.swift` | Global Carbon hotkeys without injecting input into AoE2 |
| `Resources/builds.json` | Starter training plans (placeholders) |
| `XSBuildExporter.swift` | Turns a selected JSON build into standalone XS source |
| `TrainingModPackager.swift` | Creates a local AoE2 mod with RMS + XS without overwriting game files or existing mods |
| `Resources/trainer_template.xs` | XS rolling economy metrics and game-native instruction panel |

## Next milestones

1. Verify overlay placement and hotkeys against the official macOS Steam build.
2. Validate the auto-installed local mod and `#include_drs` wrapper in a native Mac Steam custom RMS, including whether the instruction panel refreshes correctly.
3. Validate XS total-collected counters, timed checkpoint status, unit counts and approximate worker classifications during a 1v1 against AI, including villager drop-off, farms and fishing.
4. Improve JSON plans with validated first-ten-minute milestones; add in-game build selection / manual navigation if the game exposes a safe XS input mechanism.
5. Research an officially supported in-game to native-app bridge; do not assume `.xsdat` supports live transfer. The engine's per-unit `cUnitActionId` may help diagnose TC state, but whether training is reflected reliably is unverified; do **not** label derived guesses as exact TC idle time.
6. Defer replay parsing and post-game analytics until the live trainer is useful.

Online competitive use of scripted coaching has not been verified against the game's fair-play policy. Until that is clarified, use the XS-enhanced features in explicitly supported custom single-player training maps.

## XS references

- [Official XS functions](https://www.forgottenempires.net/age-of-empires-ii-definitive-edition/xs-scripting-in-age-of-empires-ii-definitive-edition)
- [Resource IDs 166–169: total collected](https://ugc.aoe2.rocks/general/resources/resources/)
- [2026 `xsDisplayInstructions` update](https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-177723/)
- [2026 `xsUnsyncGetLocalPlayerId` rename](https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-185872/)
- [XS sidecar buffering limitations](https://github.com/chrae/aoe2kit/blob/main/docs/SIDECAR.md)

## License

MIT — see [LICENSE](LICENSE). Implementation is original; no code was copied from source-available, non-redistributable overlays.
