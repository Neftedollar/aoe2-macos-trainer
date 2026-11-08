# AoE2 Mac Trainer

A native macOS training HUD for **Age of Empires II: Definitive Edition**, designed for the official Apple Silicon edition on Steam.

The goal is to help 1v1 players practice unfamiliar civilizations without leaving their match. The overlay floats over the game and lets mouse clicks pass through to AoE2.

## Current status (v0.1 prototype)

- Native transparent `NSPanel` overlay (SwiftUI + AppKit)
- Click-through window with support for macOS fullscreen Spaces
- Menu-bar controller; no Dock icon
- Global hotkeys for build navigation, build selection, overlay visibility and timer control
- Five sample builds: generic scouts, archers, Arena Fast Castle, Portuguese Fast Castle, Spanish Castle Drop
- Training timer calibrated to **1.7x** normal AoE2 game speed
- XCTest unit tests and GitHub Actions macOS build

**Not implemented yet:** reading AoE2's live HUD, automatically detecting the civilization/map, auto-advancing build steps, exact TC idle time, and resource income/efficiency. The current timer is an **estimate**, started by hand; it cannot detect in-game pauses. All sample target timings are unverified training placeholders, **not competitive reference benchmarks**.

## Get started

Requires a Mac with macOS 13 or later and Xcode Command Line Tools or Xcode.

```sh
swift test
bash Scripts/build-app.sh
open .build/AoE2MacTrainer.app
```

The app appears as 🏰 in the macOS menu bar. Launch AoE2 DE in **Windowed/Borderless** mode if the overlay does not appear over native fullscreen. Click-through is enabled permanently; all controls are via the menu-bar icon or global hotkeys.

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

## Next milestones

1. Verify overlay placement and hotkeys against the official macOS Steam build.
2. Add ScreenCaptureKit + Vision OCR and HUD-region calibration for game clock, villagers and resource counts.
3. Convert training benchmarks into real civ/map-specific targets, derived from verified replays.
4. Detect TC production gaps as precisely as screen-only observations allow. Provide uncertainty indicators where observations are incomplete.
5. Add post-game replay analysis and experimental gross gather-rate estimates; net resource-stockpile deltas alone do **not** measure resource income because spending alters the stockpile.

Online competitive use of automatic in-game coaching has not been verified against the game's fair-play policy. Until that is clarified, use enhanced prompts/alerts in single-player training.

## License

MIT — see [LICENSE](LICENSE). Implementation is original; no code was copied from source-available, non-redistributable overlays.
