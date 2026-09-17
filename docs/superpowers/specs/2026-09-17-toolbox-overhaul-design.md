# Xeneon Toolbox overhaul — design

Date: 2026-09-17 · Branch: `toolbox-apps` (on top of the uncommitted deck-pages / remote-token work)

## Goals (from the request)

1. Stop the app draining CPU, especially on the Dashboard.
2. Give the UI real depth and design it for the Edge's 2560×720 strip.
3. Detect a wrong Edge resolution and guide the user to fix it (one tap where possible).
4. Remove the Games section.
5. Add genuinely useful gadgets.
6. Fix "touch stops working until I re-toggle it".

## Evidence gathered before designing

- The installed app (v1.17.0, pid 432) has averaged **45% CPU over 6 days** of uptime; it is on the Dashboard in full mode. WindowServer sits at ~130%.
- A 5 s `sample` of the live process: the hot leaf frames are SwiftUI layout (`StackLayout`, `UnaryLayoutEngine.sizeThatFits`, `AGGraphGetInputValue`, text metrics), i.e. **re-layout churn**, not our own code. Two utility threads sit in `NSTask.waitUntilExit` — the media poller spawning `osascript` every 2 s.
- Structural causes in code: `RootView` observes `SystemMetrics`, so every 1.5 s tick re-evaluates the whole panel; `DashboardView` observes the god-object `ToolboxModel`, which also publishes 60 Hz gesture values (`controlExt`, `pullFrac`); the clock tile re-lays-out its entire content every second; every tile, ring, sparkline and bar carries a Gaussian `.shadow` that re-rasterizes on each change; `MediaController` publishes a fresh value every 2 s whether or not anything changed.
- Display: macOS flags **1920×1080 as the Edge's default mode**; the native 2560×720 mode (ioModeID 28) is **not returned by the public `CGDisplayCopyAllDisplayModes`** on this Mac, but it is visible through the private CGS mode list (`CGSGetDisplayModeDescriptionOfLength`) that displayplacer uses, and `CGSConfigureDisplayMode` is available. Identity: vendor 3672 / model 60672, `NSScreen.localizedName` = "XENEON EDGE".
- Every Edge lookup in the app matches **exact 2560×720 point geometry** (5 duplicated matchers: `AppDelegate.edgeScreen`, `HIDSupport.findEdgeDisplay`, `WindowMover.displays`, `ToolboxModel.edgeOrigin/edgeDisplayActive`). In any other mode the kiosk is not placed, touch mapping has no display rect, and the recovery watchdog thinks the panel is asleep.
- App log (Sep 2026): recovery cycles on dark wakes work as designed (`displays woke → connected → seize OK`). Today shows repeated bursts of `Edge display appeared — reacquiring digitizer` with **no rebuild** afterwards: `reacquireTouch()` returns early when the device looks "detected and seized", so the driver keeps a **display rect captured once at connect** even after the screen arrangement changes. Seize never failed on this machine (0 of 513), so the retry-cap path is not the cause here, but its hard stop after 5 attempts is still a "dead until re-toggle" trap elsewhere.
- Gadget feasibility: SoC temperatures and fan RPM are readable from the SMC without root on this M3 Ultra (586 temperature keys, 2 fans, 30 reads ≈ 7 ms). The HID sensor route returns nothing on macOS 26 here, so SMC is the path.

## Approaches considered

- **Performance**: (A) micro-tuning only (shadows, cadence) — low risk, partial gains. **(B) restructure observation + single-frame metrics + event-driven media + shadow discipline — recommended; it attacks what the sample shows.** (C) rewrite the dashboard in Core Animation — overkill.
- **Dashboard**: (A) keep one row of eight tall columns and polish. **(B) two-row, mixed-size widget grid with a tile gallery — recommended; the strip is 3.5:1, one row wastes half of every tile.** (C) free-form canvas — over-engineered for touch.
- **Resolution**: (A) instructions only. **(B) detect + guide + one-tap fix via the CGS mode API (displayplacer precedent), with manual fallback — recommended.** (C) silently switch on launch — surprising and hard to undo.

## 1. Remove Games

- Delete `GamesView.swift`; move `GameWebView` into `BrowserView.swift` as `PanelWebView` (the browser is its only remaining user); drop `WebLoadState`.
- `AppRoute` loses `.games`; tabs become Dashboard, Deck, Clock, Tasks, Assistant (Web stays a hidden route).
- `ToolboxModel.gamePref`, the assistant's `open_game` tool, its prompt/labels and the "Play Rhythm Plus" chip go; the chip becomes "Remind me…". Remote page list and icon drop Games. README loses the Games bullet, section and screenshot (`docs/img/games.png` deleted).

## 2. Edge identity, resolution guide, touch reliability

### 2a. One Edge locator

`EdgeDisplayLocator` (public, in `XeneonTouchDriver`) replaces the five geometry matchers:

- Identity, in order: vendor 3672 + model 60672 → display name contains "XENEON" → the CGS mode list contains a 2560×720 mode. Returns `EdgeDisplay { id, bounds (top-left global), pointSize, pixelSize, refreshHz, isNativeMode }`.
- The kiosk, the touch mapping, WindowMover's display list, the watchdog's "display present" check and the long-press origin all use it. The kiosk therefore covers the Edge in **any** mode, and touch maps onto whatever bounds it currently has.

### 2b. Resolution guide

- `DisplayModeAdvisor` checks on launch and on every `didChangeScreenParameters`: Edge present and mode ≠ 2560×720 @1× → `model.displayIssue = .wrongMode(current:, recommended:)`.
- `ResolutionGuideView` overlays the kiosk: what's wrong (macOS picked a scaled mode, the panel is being stretched and the UI can't fit), primary **"Use 2560 × 720"** (applies the native mode through `CGBeginDisplayConfiguration` + `CGSConfigureDisplayMode` + `CGCompleteDisplayConfiguration(.permanently)`, with a 15 s **Undo** that restores the previous mode), secondary **"Open Display Settings"** (deep link) plus three manual steps for the case where the mode is hidden (hold ⌥ and click Scaled → choose 2560 × 720). "Later" remembers the dismissed mode string, so it only reappears if the mode changes again.
- Settings gains a **Display** row: "XENEON EDGE · 2560 × 720 @ 60 Hz ✓" or the same Fix button.
- The no-Edge window becomes a proper "Connect your Xeneon Edge" screen (today it is just a title bar).
- Pure `EdgeModeChooser.best(from:)` (pick 2560×720 @1×, highest refresh, prefer safe) is unit-tested.

### 2c. Touch fixes

- **T1 stale rect**: `TouchService.refreshDisplay()` re-reads the Edge bounds on the driver thread without teardown; called on every screen-parameters change and on each healthy watchdog tick (only publishes if the rect changed).
- **T2 identity**: `findEdgeDisplay` uses the locator (2a).
- **T3 retry trap**: `TouchRecoveryPolicy` keeps 5 fast seize retries, then keeps retrying every 10th tick (~1 min) forever instead of stopping. Tests updated.
- **T4 stuck gesture**: the mid-gesture watchdog also clears edge-swipe state (`edgeKind`, `edgeSuppress`, `top/bottom/sideActive`).
- **T5 wake events**: `reacquireSoon()` (system wake, screen unlock, display (re)appeared) always rebuilds the driver; the "healthy so skip" guard stays only for the periodic watchdog. A rebuild costs ~100 ms and nobody is touching the panel during a wake.
- **T6 partial removal**: `deviceRemoved` receives the device; removal of a secondary WCH interface no longer tears down the live digitizer.
- Diagnostics: the driver exposes `lastReportAt`; Settings → About shows "Touch: active · last input 4 s ago" and a one-tap **Restart touch**.

## 3. Performance

- **Observation scoping**: `RootView` keeps a plain reference to `SystemMetrics`; gesture values (`controlExt`, `pullFrac`, `deckLongPressAt`) move to a small `PanelGestures` object observed only by the overlays that draw them; `DashboardView` observes only the metrics frame and its layout store; `NavRail` badges/dots become leaf views that observe the todo store / focus timer themselves.
- **Metrics**: one `@Published frame: MetricsFrame` (snapshot + histories) per tick; sampling on a utility queue with cached IOKit services; cadence 2 s while the Dashboard is on screen, 6 s elsewhere and on the ambient screen, stopped in sleep (already).
- **Clock**: HH:MM ticks per minute; the seconds readout is its own 1 s `TimelineView` inside a fixed-width frame (Clock page only — the dashboard tile shows no seconds).
- **Media**: `MediaController` switches to `DistributedNotificationCenter` events (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`) with a 20 s safety poll only while a player runs and a now-playing surface is visible; publishes only on change. The 2 s `osascript` spawn loop is gone.
- **Rendering**: ambient shadow only on the tile background shape; the glow on animated shapes (ring, sparkline, capacity bar) becomes a wide low-alpha stroke instead of a blur; sparklines render in a `drawingGroup`; readouts use `contentTransition(.numericText())`.
- Kiosk front-pin timer 1 s → 2 s (same semantics).
- **Targets** (dev build, devMode window, measured with `top`): Dashboard ≤ 8% CPU steady, ambient ≤ 3%, no subprocess spawns while idle. Before/after numbers go in the report.

## 4. Dashboard redesign and depth

Screen: 2560×720 pt, ~188 ppi, finger-operated. Available content area after a 112 pt rail and 20 pt insets: 2408×680.

- **Rail**: 188 pt labeled list → **112 pt icon rail**. Finger targets stay big: each destination is an 88×76 pt hit area (icon 24 pt + 12 pt label), accent pill on the active item. Bottom: touch status dot (tap toggles touch), and one "⋯" button (88×64 pt) opening a small sheet: Full screen · Ambient · Sleep · Hide to badge · Settings · Quit. Frees 76 pt for content.
- **Widget grid**: 2 rows × 8 columns; sizes **S** 1×1 (≈287×332), **W** 2×1 (≈590×332), **T** 1×2 (≈287×680), **L** 2×2. A tile declares its supported sizes; a first-fit packer places tiles in order. Layout persists as `dashboard.layout.v2` (ids + sizes); v1 order migrates, `controls` is dropped.
- **Default board (16 cells)**: Clock T · CPU S · GPU S · Memory S · Network W · Storage S · Power S · Up Next W · Tasks S · Thermals S · Dock W · Now Playing S.
- **Edit mode**: enter by long-press on the board or from the "⋯" sheet; drag to reorder in 2-D (reuses the deck's `dragAnywhere` driver mode); ⊖ to remove; a size toggle on tiles that support more than one size; **Add** opens a **tile gallery** (every tile type not on the board, with a size preview and "N of 16 cells used"). Replaces the hidden-tile tray.
- **Configs tile removed**: touch toggle → rail + Control Centre; calibration → Settings; edit → long-press / sheet.
- **Now Playing** becomes a tile (artwork, title, transport; tap for the full player). The bottom bar stays on the ambient screen only.
- **Depth pass (Theme v2)**: three elevations — base (panel wash), surface (tile: gradient, 1 px inner highlight, hue-tinted edge, ambient shadow on the shape), raised (modals/Control Centre: material + deep shadow). Gauges/graphs sit in recessed "wells". Locked type scale: label 12/1.8, caption 13, body 15, title 17, readout 44 (S) / 58 (W, T hero). Pressure semantics on CPU, memory, storage, thermals: amber ≥ 75%, red ≥ 90%. Numeric readouts animate. Ambient screen adopts the same scale.
- Verification renders (XENEON_RENDER) of dashboard, edit mode, gallery, ambient, resolution guide; README screenshots regenerated.

## 5. New gadgets (tiles)

- **Up Next** (W/S): next three events today with calendar colour and time, "now" highlighted; tap → agenda. Uses the existing `CalendarService.today`.
- **Tasks** (S/W): overdue/today counts; next open items with a tappable checkbox; header → Tasks tab.
- **Thermals** (S): SoC temperature (max of the CPU cluster keys `Tp*`/`Tc*`/`Te*`, falling back to any `T*`), GPU (`Tg*`), fan RPM (`F?Ac`; hidden when `FNum` = 0). `SMCReader` opens `AppleSMC` unprivileged, reads ~10 keys per 5 s tick on the metrics cadence, and degrades to "unavailable". Ring gauge with amber ≥ 85 °C, red ≥ 95 °C.
- **Dock** (W): running apps as icons (regular activation policy), frontmost highlighted; tap → bring forward on the main display (`WindowMover.openOffEdge`); long-press → the deck's screen picker. Driven by workspace notifications, no polling.
- **Clipboard** (S/W): last six text clips (1 s `changeCount` poll, reads only on change); tap → copy back; ⓧ removes; pause toggle in the header; in-memory only, never persisted.
- **Network detail** gains SSID, local IP and public IP rows (hourly fetch) — small.
- Deferred: stock/crypto tickers, per-device Bluetooth battery.

## 6. Verification and docs

- `swift build` + `swift test` (new: recovery backoff, mode chooser, grid packer, clipboard model).
- CPU before/after with `top` on the dev build (dashboard and ambient), reported in the summary.
- Headless renders for every changed screen; README updated (Games removed, tiles, resolution guide, touch reliability); screenshots regenerated.
- No version bump or release unless asked. Commits only on request.

## Decisions (2026-09-17)

1. Design approved as written.
2. Rail: compact, but every nav item must stay easy to press with a finger → 112 pt rail with 88×76 pt targets (see §4).
3. The resolution auto-fix may be exercised once on the connected Edge (1920×1080 and back).
4. Gadgets: Up Next, Tasks, Thermals, Dock, Clipboard — all in.
