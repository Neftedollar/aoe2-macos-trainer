# AoE2 Mac Trainer

A native macOS training HUD for **Age of Empires II: Definitive Edition**, designed for the official Apple Silicon edition on Steam.

The goal is to help 1v1 players practice unfamiliar civilizations without leaving their match. The overlay floats over the game and lets mouse clicks pass through to AoE2.

## Current status (v0.3 experimental)

- Native transparent `NSPanel` overlay (SwiftUI + AppKit)
- Click-through window with support for macOS fullscreen Spaces
- Menu-bar controller; no Dock icon
- Global hotkeys for build navigation, build selection, overlay visibility and timer control
- Five sample builds: generic scouts, archers, Arena Fast Castle, Portuguese Fast Castle, Spanish Castle Drop
- Training timer calibrated to **1.7x** normal AoE2 game speed
- XS script exporter that turns the selected **JSON build** into a self-contained `.xs` trainer
- Custom JSON file in `~/Library/Application Support/AoE2MacTrainer/builds.json`, reloadable from the menu without rebuilding
- Experimental in-game XS dashboard: actual game time, build steps, villager target, four **gross resource-collected rates** per rolling 60 game seconds
- Approximate number of workers assigned to each resource and per-worker rates, based on the villager task target / cargo
- XCTest unit tests and GitHub Actions macOS build

**Not implemented yet:** automatically detecting civilization/map, a verified real-time link from XS to the external macOS overlay, exact TC idle time, reliable per-worker assignment, and post-game replay analysis. The native overlay still uses an **estimated clock** started by hand; the XS instructions use the **actual in-game clock**. All sample build timings remain unverified training placeholders, **not competitive benchmarks**.

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
2. Choose **Экспорт XS для выбранного билда…** and save the generated `.xs` script.
3. In your *custom* AoE2 Random Map Script (`.rms`), add `#includeXS your_file.xs` at the top, before `<PLAYER_SETUP>`. Place the `.xs` file where that RMS can resolve it (game's `resources/_common/xs` or a compatible local mod). The exact location and installation flow of the **native Feral macOS port is not yet validated**.
4. Start a custom-map match against AI. Once the script loads, its own game-native instruction panel should display the selected build's timed target, collected resources/minute and approximate resource-worker counts. A full 60-game-second window is needed before the first rate appears.

**Important:** the native XS display is separate from the SwiftUI overlay. It follows build step *reference times*, whereas the macOS overlay's steps are manually controlled by hotkeys. The XS panel is placed by AoE2 at its built-in **top instruction position** (about 13% from the top), not at an arbitrary pixel coordinate. Neither runtime gameplay nor script loading on macOS has been verified yet.

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
| `Resources/trainer_template.xs` | XS rolling economy metrics and game-native instruction panel |

## Next milestones

1. Verify overlay placement and hotkeys against the official macOS Steam build.
2. Validate XS script execution in a native Mac Steam custom RMS, including custom mod deployment paths and whether the instruction panel refreshes correctly.
3. Validate XS total-collected counters and approximate worker classifications during a 1v1 against AI, including villager drop-off, farms and fishing.
4. Improve JSON plans with validated first-ten-minute milestones; add explicit target completion semantics and manual navigation inside game when possible.
5. Research an officially supported in-game to native-app bridge; do not assume `.xsdat` supports live transfer. Add exact TC production idle metrics if data permits.
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
