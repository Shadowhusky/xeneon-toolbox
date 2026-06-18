# Xeneon Toolbox

A macOS toolbox for the **Corsair Xeneon Edge** (14.5", 2560×720 touchscreen).
It makes the panel genuinely useful on a Mac in two ways:

1. **Touch driver** — macOS sees the Edge's digitizer but only produces vague
   relative cursor motion ("touch board"). The toolbox reads the panel's
   absolute coordinates and injects real pointer events, so taps and drags land
   where you touch.
2. **Status panel** — a telemetry deck designed to fill the 2560×720 screen:
   live CPU, memory, network, storage, power, and a clock, with hue-coded ring
   gauges and sparklines. Tap **Minimize** to collapse it to a slim bar.

The touch driver is **embedded in the app** — while Xeneon Toolbox is running,
touch works. No LaunchAgent, no kernel extension, no sudo.

![Expanded panel](docs/panel-expanded.png)
![Minimized bar](docs/panel-minimized.png)

## Build & run

```bash
swift build -c release        # build everything
swift test                    # unit tests for the core logic

./scripts/make-app.sh         # produce XeneonToolbox.app
open XeneonToolbox.app        # run it (renders on the Edge)
```

### Permissions

Grant **Xeneon Toolbox** both in *System Settings → Privacy & Security*:

- **Input Monitoring** — to read the touch digitizer
- **Accessibility** — to inject clicks (without it, clicks are silently dropped)

If you were running the `xeneon-touch` CLI for touch, quit it first — only one
process can hold the digitizer.

## Layout

A single Swift package with focused targets:

| Target | Kind | Purpose |
| --- | --- | --- |
| `XeneonTouchCore` | library | Pure, unit-tested logic: coordinate mapping, the tap/drag state machine, HID report decoding |
| `XeneonTouchDriver` | library | IOKit HID capture + CoreGraphics event injection; `TouchService` start/stop |
| `XeneonToolbox` | app | SwiftUI status panel + embedded touch driver |
| `xeneon-touch` | CLI | Diagnostics (`diagnose`, `list-displays`) and headless `run` |

## Hardware notes (Xeneon Edge)

- Touch digitizer: WCH HID controller `0x27c0:0x0859` (3 HID interfaces).
- Reports as a mouse-style absolute device: X = GenericDesktop `0x30`,
  Y = GenericDesktop `0x31`, contact = Button page `0x09` / Button 1.
- Coordinate ranges: X `0…16383`, Y `0…9599`.
- macOS holds the digitizer exclusively, so the driver runs non-exclusively and
  injects absolute events alongside the system.

## CLI diagnostics

```bash
swift run xeneon-touch diagnose       # confirm device + live HID reports
swift run xeneon-touch list-displays  # display ids and bounds
```

If taps land mirrored or rotated, the driver supports `--flip-x`, `--flip-y`,
and `--swap-xy`.
