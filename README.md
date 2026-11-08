# AoE2 Mac Trainer

A native macOS training HUD for **Age of Empires II: Definitive Edition**, designed for the official Apple Silicon edition on Steam.

The goal is to help 1v1 players practice unfamiliar civilizations without leaving their match. The overlay floats over the game and lets mouse clicks pass through to AoE2.

## Current status (v0.2 prototype)

- Native transparent `NSPanel` overlay (SwiftUI + AppKit)
- Click-through window with support for macOS fullscreen Spaces
- Menu-bar controller; no Dock icon
- Global hotkeys for build navigation, build selection, overlay visibility and timer control
- Five sample builds: generic scouts, archers, Arena Fast Castle, Portuguese Fast Castle, Spanish Castle Drop
- Training timer calibrated to **1.7x** normal AoE2 game speed
- Optional on-device ScreenCaptureKit + Vision OCR for game clock, villagers and resource stockpiles (requires macOS 14+)
- Visual one-time HUD calibration: draw boxes around relevant numbers in a screenshot
- Per-resource **net stockpile delta / game minute** over a recent window, including spending (not gross gathering)
- XCTest unit tests and GitHub Actions macOS build

**Not implemented yet:** automatically detecting the civilization/map, auto-advancing build steps, exact TC idle time, and resource **income/efficiency**. Without configured OCR, the timer is an **estimate**, started by hand; it cannot detect in-game pauses. With OCR, clock readings are taken from the game. The sample build timings are unverified training placeholders, **not competitive reference benchmarks**.

## Get started

Requires a Mac with macOS 13 or later and Xcode Command Line Tools or Xcode.

```sh
swift test
bash Scripts/build-app.sh
open .build/AoE2MacTrainer.app
```

The app appears as 🏰 in the macOS menu bar. Launch AoE2 DE in **Windowed/Borderless** mode if the overlay does not appear over native fullscreen. Click-through is enabled permanently; all controls are via the menu-bar icon or global hotkeys.

### Live HUD recognition (experimental)

1. Start AoE2 on the display you intend to use; leave its resource bar visible.
2. From the trainer's 🏰 menu choose **Настроить захват HUD…**. macOS may ask for Screen Recording permission. The app never uploads or saves screenshots.
3. Select **Время**, drag a tight box around the game's clock digits; repeat for **Крестьяне**, **Еда**, **Дерево**, **Золото**, **Камень**. You can configure only the fields you want. Save.
4. The trainer reads the configured regions every ~2 seconds. **◉** next to the overlay clock means it came from OCR; **≈** means the manually started estimate. The resource rate is displayed only after enough observations.
5. Use the menu item **Остановить чтение HUD** whenever you do not want the trainer to capture your screen. Capture permission and calibration are local to your Mac.

Calibration depends on your display resolution, AoE2 UI scale, and game-window placement. Reconfigure after changing those. OCR can misread numbers; cross-check with the game's HUD. If the overlay obscures content or is not visible in fullscreen, switch the game to borderless window mode. **No memory injection or input automation is used.**

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
2. Validate live HUD calibration, screenshot permissions, OCR accuracy, and resource charts against the native Steam build.
3. Convert training benchmarks into real civ/map-specific targets, derived from verified replays.
4. Detect TC production gaps as precisely as screen-only observations allow. Provide uncertainty indicators where observations are incomplete.
5. Add post-game replay analysis and experimental gross gather-rate estimates; net resource-stockpile deltas alone do **not** measure resource income because spending alters the stockpile.

Online competitive use of automatic in-game coaching has not been verified against the game's fair-play policy. Until that is clarified, use enhanced prompts/alerts in single-player training.

## License

MIT — see [LICENSE](LICENSE). Implementation is original; no code was copied from source-available, non-redistributable overlays.
