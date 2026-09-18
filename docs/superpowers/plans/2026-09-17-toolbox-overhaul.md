# Xeneon Toolbox Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the app's idle CPU from ~45% to single digits, make touch survive display changes and wakes without a manual re-toggle, detect and fix a wrong Edge resolution, remove Games, and rebuild the Dashboard as a two-row widget grid with five new gadgets.

**Architecture:** Keep the existing SwiftUI + ObservableObject app, but split the frequently-changing state (gestures, metrics frame) into small observed objects so ticks only re-render the tiles that use them. A single `EdgeDisplayLocator` identifies the panel by vendor/model/name instead of pixel geometry and feeds the kiosk, the touch mapping and the resolution advisor. The dashboard becomes a packed 2×8 grid driven by a pure `GridPacker`.

**Tech Stack:** Swift 6 toolchain (language mode 5 for the app target), SwiftUI, AppKit, IOKit (HID, SMC, IOReport), CoreGraphics + private CGS display-mode calls resolved with `dlsym`, XCTest via `swift test`.

**Spec:** `docs/superpowers/specs/2026-09-17-toolbox-overhaul-design.md`

## Global Constraints

- macOS 14+ deployment target; Swift tools 6.0; app target compiled in Swift language mode 5 (`Package.swift`).
- Build: `swift build`; tests: `swift test`; app bundle: `./scripts/make-app.sh`; headless screenshot: `XENEON_RENDER="<route>@<scale>@<warmupSeconds>@/abs/out.png" .build/debug/XeneonToolbox`.
- Never commit unless the user asks. No version bump, no release.
- Follow the existing style: `Theme.*` colours, `.deck()` / `.readout()` fonts, `.pressable` button style, `Motion.*` animations, `AppLog.info/error(tag, message)` logging, comments only for non-obvious rules.
- Touch targets ≥ 44 pt; nav rail items 88×76 pt.
- The installed app (pid 432, v1.17.0) keeps running during development; a dev build cannot seize the digitizer while it runs — that is expected and must not be "fixed".
- Do not touch the uncommitted deck-pages / remote-token work except where a task names the file.

---

## Phase 0 — Baseline

### Task 0: Dev-window placement env + CPU baseline

**Files:**
- Modify: `Sources/XeneonToolbox/AppDelegate.swift:184-195` (devMode branch of `placeWindow`)

**Interfaces:**
- Produces: env `XENEON_DEV_FRAME="x,y,w,h"` (Cocoa bottom-left coordinates) that positions the devMode window; used by every measurement task.

- [ ] **Step 1: Add the env hook in the devMode branch of `placeWindow()`**

```swift
if devMode {
    stopYieldWatch()
    win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel]
    win.becomesKeyOnlyIfNeeded = false
    win.isFloatingPanel = false
    win.level = .normal
    // Dev measurement hook: place the window explicitly (Cocoa coordinates).
    if let spec = ProcessInfo.processInfo.environment["XENEON_DEV_FRAME"] {
        let v = spec.split(separator: ",").compactMap { Double($0) }
        if v.count == 4 { win.setFrame(NSRect(x: v[0], y: v[1], width: v[2], height: v[3]), display: true) }
    }
    win.makeKeyAndOrderFront(nil)
    return
}
```

- [ ] **Step 2: Build and measure the baseline (dashboard, then ambient)**

Run (each ~40 s; the window appears on the main display):
```bash
swift build 2>&1 | tail -1
XENEON_NO_FULLSCREEN=1 XENEON_DISPLAY=full XENEON_ROUTE=dashboard XENEON_DEV_FRAME="10,200,1900,720" .build/debug/XeneonToolbox & PID=$!; sleep 12; top -l 6 -s 3 -pid $PID -stats pid,cpu,mem | grep -E "^ *$PID"; kill $PID
XENEON_NO_FULLSCREEN=1 XENEON_DISPLAY=minimal XENEON_DEV_FRAME="10,200,1900,720" .build/debug/XeneonToolbox & PID=$!; sleep 12; top -l 6 -s 3 -pid $PID -stats pid,cpu,mem | grep -E "^ *$PID"; kill $PID
```
Record the median CPU of samples 2–6 for both modes in `docs/superpowers/plans/measurements.md` (create it) as the "before" row. Also render `XENEON_RENDER="dashboard@1@4@<scratch>/before-dashboard.png"` and `minimal@1@4@…/before-minimal.png` for the visual before/after.

---

## Phase 1 — Remove Games

### Task 1: Delete the Games route and every reference

**Files:**
- Delete: `Sources/XeneonToolbox/UI/GamesView.swift`, `Sources/XeneonToolbox/UI/WebGameView.swift`, `docs/img/games.png`
- Modify: `Sources/XeneonToolbox/UI/BrowserView.swift` (add `PanelWebView`), `Sources/XeneonToolbox/ToolboxModel.swift:8-50,151`, `Sources/XeneonToolbox/AgentController.swift:296-304,397-400,804-809,891-895`, `Sources/XeneonToolbox/UI/ChatView.swift:140`, `Sources/XeneonToolbox/RemoteServerHTML.swift:229,261`, `Sources/XeneonToolbox/UI/PanelView.swift:197-227`, `Sources/XeneonToolbox/UpdateChecker.swift:228`, `README.md`

**Interfaces:**
- Produces: `final class PanelWebView: WKWebView` (the former `GameWebView`, same behaviour) in `BrowserView.swift`; `AppRoute` cases `dashboard, deck, clock, tasks, web, chat`.

- [ ] **Step 1: Move `GameWebView` into `BrowserView.swift` as `PanelWebView`** (copy the class body verbatim, rename, update the two `GameWebView` references in `WebController` and `WebPane`; drop `WebLoadState`).
- [ ] **Step 2: Delete `GamesView.swift`, `WebGameView.swift`, `docs/img/games.png`.**
- [ ] **Step 3: Remove `.games` from `AppRoute`** (title/icon/accent switches), delete `gamePref` from `ToolboxModel`, delete the `case .games:` line in `RootView.content`, and simplify `contentInset` to `model.route == .web ? 0 : 14`.
- [ ] **Step 4: Assistant**: remove the `open_game` tool, its `runTool` case and `toolLabels` case; `navigate` enum → `["dashboard", "deck", "clock", "tasks", "web", "assistant"]`; system prompt tab list → "Dashboard (live system telemetry, weather, calendar, tasks, thermals, running apps, clipboard), Deck (a Stream-Deck launcher), Clock (world clocks + focus timer), Tasks (to-dos and reminders), Web (an embedded browser — use open_url), and Assistant (you)"; guideline line → "Only use navigate when the user explicitly asks to switch tabs".
- [ ] **Step 5: ChatView chip** → `.init(icon: "bell.badge.fill", label: "Remind me", prompt: "Remind me to stretch in 30 minutes", tint: Theme.battery)`.
- [ ] **Step 6: Remote HTML**: delete the `games:` SVG entry and the `['games','games','Games']` page entry.
- [ ] **Step 7: README**: remove the Games bullet in Highlights, the "### Games" section and screenshot, and "and games" from the intro sentence. `UpdateChecker.demo()` notes: replace "games and the browser go fully immersive" with "the browser goes fully immersive".
- [ ] **Step 8: Verify** `swift build` succeeds and `grep -rni "game" Sources --include='*.swift'` only matches `SystemToggles.swift:387` (Bluetooth gamepad symbol) and the `GameWebView`-free browser.

---

## Phase 2 — Edge identity, resolution guide, touch reliability

### Task 2: `EdgeDisplayLocator` + CGS display modes + mode chooser (with tests)

**Files:**
- Create: `Sources/XeneonTouchDriver/EdgeDisplay.swift`, `Sources/XeneonTouchCore/EdgeModeChooser.swift`, `Tests/XeneonTouchCoreTests/EdgeModeChooserTests.swift`
- Modify: `Sources/XeneonTouchDriver/HIDSupport.swift:73-87` (`findEdgeDisplay` delegates to the locator)

**Interfaces (produces):**
```swift
// XeneonTouchCore — pure, testable
public struct DisplayModeCandidate: Equatable, Sendable {
    public let number: Int32; public let width: Int; public let height: Int
    public let density: Double; public let flags: UInt32
    public init(number: Int32, width: Int, height: Int, density: Double, flags: UInt32)
    public var isSafe: Bool { flags & 0x2 != 0 }
}
public enum EdgeModeChooser {
    public static let nativeWidth = 2560, nativeHeight = 720
    /// The 2560×720 @1× mode to recommend: safe-flagged first, then lowest mode number.
    public static func best(from modes: [DisplayModeCandidate]) -> DisplayModeCandidate?
    public static func isNative(width: Int, height: Int, pixelWidth: Int) -> Bool
}

// XeneonTouchDriver
public struct EdgeDisplay: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let bounds: CGRect            // CGDisplayBounds (top-left global)
    public let pointSize: CGSize, pixelSize: CGSize
    public let refreshHz: Double
    public var isNativeMode: Bool
    public var rect: DisplayRect
}
public enum EdgeDisplayLocator {
    public static let vendorNumber: UInt32 = 3672, modelNumber: UInt32 = 60672
    /// Identity: vendor+model → nameHint contains "XENEON" → CGS mode list has a 2560×720 mode.
    public static func current(nameHint: (CGDirectDisplayID) -> String? = { _ in nil }) -> EdgeDisplay?
    public static func isEdge(_ id: CGDirectDisplayID, nameHint: (CGDirectDisplayID) -> String?) -> Bool
}
public enum CGSDisplayModes {
    public static func all(for id: CGDirectDisplayID) -> [DisplayModeCandidate]   // private CGSGetNumberOfDisplayModes/CGSGetDisplayModeDescriptionOfLength (0xD4 bytes: number@0, flags@4, width@8, height@12, density@0xD0)
    public static func current(for id: CGDirectDisplayID) -> Int32?              // CGSGetCurrentDisplayMode
    public static func apply(_ number: Int32, to id: CGDirectDisplayID) -> Bool  // CGBeginDisplayConfiguration + CGSConfigureDisplayMode + CGCompleteDisplayConfiguration(.permanently)
}
```

- [ ] **Step 1: Write the failing tests** (`EdgeModeChooserTests.swift`):
```swift
import XCTest
@testable import XeneonTouchCore
final class EdgeModeChooserTests: XCTestCase {
    func testPrefersSafeNativeMode() {
        let modes = [DisplayModeCandidate(number: 28, width: 2560, height: 720, density: 1, flags: 0x1),
                     DisplayModeCandidate(number: 40, width: 2560, height: 720, density: 1, flags: 0x3),
                     DisplayModeCandidate(number: 26, width: 1920, height: 1080, density: 1, flags: 0x2000007)]
        XCTAssertEqual(EdgeModeChooser.best(from: modes)?.number, 40)
    }
    func testIgnoresHiDPIDuplicate() {
        let modes = [DisplayModeCandidate(number: 9, width: 1280, height: 360, density: 2, flags: 0x1),
                     DisplayModeCandidate(number: 28, width: 2560, height: 720, density: 1, flags: 0x1)]
        XCTAssertEqual(EdgeModeChooser.best(from: modes)?.number, 28)
    }
    func testNilWhenNoNativeMode() {
        XCTAssertNil(EdgeModeChooser.best(from: [DisplayModeCandidate(number: 26, width: 1920, height: 1080, density: 1, flags: 0x7)]))
    }
    func testIsNative() {
        XCTAssertTrue(EdgeModeChooser.isNative(width: 2560, height: 720, pixelWidth: 2560))
        XCTAssertFalse(EdgeModeChooser.isNative(width: 1280, height: 360, pixelWidth: 2560))
        XCTAssertFalse(EdgeModeChooser.isNative(width: 1920, height: 1080, pixelWidth: 1920))
    }
}
```
- [ ] **Step 2: Run** `swift test --filter EdgeModeChooserTests` → fails to compile (types missing).
- [ ] **Step 3: Implement `EdgeModeChooser`** (`best`: filter width/height/density==1, sort by `(isSafe ? 0 : 1, number)`, first) and `EdgeDisplay.swift` per the interfaces. Resolve CGS symbols once with `dlsym` on `CoreGraphics.framework`; every call returns nil/false when a symbol is missing. `current(nameHint:)` iterates `CGGetActiveDisplayList`, checks vendor/model, then `nameHint(id)?.uppercased().contains("XENEON")`, then `CGSDisplayModes.all(for:).contains { $0.width == 2560 && $0.height == 720 }`; builds `EdgeDisplay` from `CGDisplayBounds` and `CGDisplayCopyDisplayMode` (`width/height/pixelWidth/pixelHeight/refreshRate`).
- [ ] **Step 4: `findEdgeDisplay(preferred:)`** → if preferred id given keep the old bounds path, else `EdgeDisplayLocator.current()?.rect`.
- [ ] **Step 5: Run** `swift test --filter EdgeModeChooserTests` → PASS; `swift build`.

### Task 3: Replace the five geometry matchers in the app

**Files:**
- Modify: `Sources/XeneonToolbox/AppDelegate.swift:405-409` (`edgeScreen`), `Sources/XeneonToolbox/WindowMover.swift:18-40`, `Sources/XeneonToolbox/ToolboxModel.swift:628-649`, `Sources/XeneonToolbox/Backlight.swift` (unchanged — m1ddc name match is fine)

**Interfaces (produces):**
```swift
// app-side helper (new file Sources/XeneonToolbox/EdgeScreen.swift)
enum EdgeScreen {
    static func nameHint(_ id: CGDirectDisplayID) -> String?      // NSScreen.localizedName lookup
    static func current() -> EdgeDisplay?                          // EdgeDisplayLocator.current(nameHint:)
    static func nsScreen() -> NSScreen?
    static var isPresent: Bool
    static var origin: CGPoint
}
```
- [ ] **Step 1: Create `EdgeScreen.swift`** and route `AppDelegate.edgeScreen()`, `WindowMover.displays()` (`isEdge = EdgeDisplayLocator.isEdge(did, nameHint: EdgeScreen.nameHint)`), `ToolboxModel.edgeOrigin()` and `edgeDisplayActive()` through it. Delete the `abs($0.frame.width - 2560) < 2` checks.
- [ ] **Step 2:** `swift build`; launch the dev build headless (`XENEON_RENDER="dashboard@1@2@…/t3.png"`) to make sure nothing crashes at startup.

### Task 4: Touch recovery policy — no permanent retry stop (with tests)

**Files:**
- Modify: `Sources/XeneonTouchCore/TouchRecoveryPolicy.swift`, `Tests/XeneonTouchCoreTests/TouchRecoveryPolicyTests.swift`, `Sources/XeneonToolbox/ToolboxModel.swift:330-350`

**Interfaces (produces):**
```swift
public static func shouldReacquire(touchOn: Bool, deviceDetected: Bool, displayPresent: Bool,
                                   seized: Bool, seizeRetries: Int, ticksSinceRetry: Int) -> Bool
// present-but-not-seized: retry while seizeRetries < 5, afterwards every 10th tick (≈1 min) forever.
```
- [ ] **Step 1: Update tests**: keep the existing five; replace `testPresentButNotSeizedRetriesUpToCap` with:
```swift
func testPresentButNotSeizedRetriesFastThenSlowForever() {
    XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 0, ticksSinceRetry: 0))
    XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 4, ticksSinceRetry: 0))
    // Past the fast budget: back off to every 10th watchdog tick, but never stop.
    XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 5, ticksSinceRetry: 3))
    XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 5, ticksSinceRetry: 10))
    XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 50, ticksSinceRetry: 10))
}
```
- [ ] **Step 2: Run** `swift test --filter TouchRecoveryPolicyTests` → compile failure. **Step 3:** implement `return !seized && (seizeRetries < 5 || ticksSinceRetry >= 10)`. **Step 4:** in `ToolboxModel.startTouchRecovery` add `private var ticksSinceRetry = 0`; increment it each tick before the policy call, reset to 0 whenever `reacquireTouch()` actually retries a seize. **Step 5:** tests PASS, build.

### Task 5: Driver fixes — refreshDisplay, wake rebuild, gesture reset, partial removal, lastReportAt

**Files:**
- Modify: `Sources/XeneonTouchDriver/TouchService.swift` (TouchDriver + TouchService), `Sources/XeneonToolbox/ToolboxModel.swift:304-365,583-591`, `Sources/XeneonToolbox/AppDelegate.swift:236-244`

**Interfaces (produces):**
```swift
public final class TouchService {
    public func refreshDisplay()          // re-read the Edge rect on the driver thread; logs "display rect → …" only on change
    public var lastReportAt: Date?        // last HID report seen (thread-safe read)
}
// ToolboxModel
func forceReacquire(reason: String)       // stop + start regardless of health flags (wake/unlock/display events)
```
- [ ] **Step 1 (T1):** `TouchDriver.refreshDisplay()`: `let fresh = findEdgeDisplay(preferred:)`; if `calSource != .none` and the rect differs (or was nil) → set `display = fresh`, `touchDiag`, and if `display` went nil→non-nil call `onPresenceChanged?(true)`. `TouchService.refreshDisplay()` performs it via `CFRunLoopPerformBlock` on the worker loop (same pattern as `flushPointer`).
- [ ] **Step 2 (T4):** in the mid-gesture watchdog closure also set `edgeKind = .none; topActive = false; topControl = false; bottomActive = false; sideActive = false; edgeSuppress = false; edgeAnchored = false`.
- [ ] **Step 3 (T6):** change `deviceRemovedCallback` to pass the device: `deviceRemoved(_ device: IOHIDDevice)`. In it: `if calSource == .digitizer, let rd = reportDevice, rd !== device { touchDiag("secondary interface removed — digitizer kept"); return }`.
- [ ] **Step 4:** record `lastReport` (CFAbsoluteTime, guarded by the service lock via a callback `onReport`) in `handleReport`/`handle(value:)`; expose `lastReportAt`.
- [ ] **Step 5 (T5):** `ToolboxModel.reacquireSoon()` → after the 1.2 s coalesce call `forceReacquire(reason:)` which logs, `touch.stop()`, `edgeDetected = false`, `attemptAcquire()`. Keep `reacquireTouch()` (guarded) for the periodic watchdog only. Healthy watchdog ticks call `touch.refreshDisplay()`.
- [ ] **Step 6:** `AppDelegate.screenParametersChanged` → `model.touch.refreshDisplay()` immediately (expose `func refreshTouchDisplay()` on the model) in addition to the existing `reacquireSoon()` when the Edge is present.
- [ ] **Step 7:** `swift build && swift test`. Manual check: run the dev build with `XENEON_TOUCH_DEBUG=1` and change the main display's refresh rate once in System Settings (or plug/unplug nothing — the notification also fires on `displayplacer`-style mode changes in Task 7); confirm `touch-debug.log` shows the refresh line.

### Task 6: `DisplayModeAdvisor` + `ResolutionGuideView` + Settings display row + no-Edge screen

**Files:**
- Create: `Sources/XeneonToolbox/DisplayModeAdvisor.swift`, `Sources/XeneonToolbox/UI/ResolutionGuideView.swift`, `Sources/XeneonToolbox/UI/NoEdgeView.swift`
- Modify: `Sources/XeneonToolbox/ToolboxModel.swift` (new published state), `Sources/XeneonToolbox/AppDelegate.swift:184-244` (call the advisor from `placeWindow`), `Sources/XeneonToolbox/UI/PanelView.swift` (overlay + no-Edge content), `Sources/XeneonToolbox/UI/SettingsView.swift` (Display + Touch rows)

**Interfaces (produces):**
```swift
struct DisplayIssue: Equatable {
    let displayID: CGDirectDisplayID
    let currentLabel: String            // "1920 × 1080"
    let recommended: DisplayModeCandidate?   // nil → manual path only
    let previousModeNumber: Int32?
}
@MainActor enum DisplayModeAdvisor {
    static func check() -> DisplayIssue?      // nil when no Edge or already native or dismissed for this mode
    static func apply(_ issue: DisplayIssue) -> Bool
    static func undo(_ issue: DisplayIssue) -> Bool
    static func dismiss(_ issue: DisplayIssue)   // AppDefaults "display.guide.dismissedMode" = currentLabel
    static func openDisplaySettings()            // x-apple.systempreferences:com.apple.Displays-Settings.extension
}
// ToolboxModel
@Published var displayIssue: DisplayIssue?
@Published var edgePresent: Bool
@Published var lastTouchInputAge: TimeInterval?   // refreshed by the watchdog tick from touch.lastReportAt
func restartTouch()                                 // stopTouch(); startTouch()
```
- [ ] **Step 1:** implement the advisor (uses `EdgeScreen.current()`, `CGSDisplayModes`, `EdgeModeChooser`).
- [ ] **Step 2:** `ResolutionGuideView(issue:onApply:onUndo:onLater:onOpenSettings:)` — a `ModalScaffold` card (920 pt wide): title "Your Xeneon Edge isn't at its native resolution", body "macOS picked <current>. The panel is 2560 × 720, so the picture is being scaled and the Toolbox can't fit the strip.", primary button "Use 2560 × 720" (only when `recommended != nil`), after applying show "Applied — Undo (15 s)" countdown using `TimelineView(.periodic(by: 1))`, secondary "Open Display Settings" + three numbered manual steps ("Choose XENEON EDGE", "Hold ⌥ and click Scaled to show all resolutions", "Pick 2560 × 720"), tertiary "Later".
- [ ] **Step 3:** `NoEdgeView` for the no-Edge window: app mark, "Connect your Xeneon Edge", "Plug the panel in over USB-C. The Toolbox moves onto it automatically." and a "Quit" button. `RootView` shows it when `!model.edgePresent && !model.exportMode`.
- [ ] **Step 4:** AppDelegate: after `placeWindow()` (both launch and screen changes) set `model.edgePresent` and `model.displayIssue = DisplayModeAdvisor.check()`.
- [ ] **Step 5:** Settings: a "Display" section (row "XENEON EDGE · 2560 × 720 @ 60 Hz" with a green check, or the current mode with a "Fix" button that sets `model.displayIssue`), and in "About" replace `touchStatusRow` with status + "last input 4 s ago" + a "Restart touch" button (`model.restartTouch()`).
- [ ] **Step 6:** render check: `XENEON_RESOLUTION_DEMO=1` env makes `check()` return a synthetic issue (current "1920 × 1080", recommended mode 28) so `XENEON_RENDER="dashboard@1@3@…/guide.png"` shows the card. Build + render + view the PNG.

### Task 7: CLI diagnostics + live hardware test of the mode switch

**Files:**
- Modify: `Sources/xeneon-touch/main.swift` (add `display-modes` and `set-mode <n>` subcommands), `README.md` (CLI table row)

- [ ] **Step 1:** `display-modes` prints `EdgeDisplayLocator.current()` and every `CGSDisplayModes.all` entry, marking the current one; `set-mode <n>` calls `CGSDisplayModes.apply`.
- [ ] **Step 2 (approved live test):** `swift build && .build/debug/xeneon-touch display-modes`, then `.build/debug/xeneon-touch set-mode 26 && sleep 4 && .build/debug/xeneon-touch set-mode 28`, then `display-modes` again → current must be 28 (2560×720). Check `~/.config/xeneon-toolbox/app.log` shows the installed app re-placing its kiosk ("Edge display appeared"). Record the result in `measurements.md`.

---

## Phase 3 — Performance

### Task 8: Single metrics frame, off-main sampling, cadence

**Files:**
- Modify: `Sources/XeneonToolbox/Metrics/SystemMetrics.swift` (rewrite), callers: `UI/DashboardView.swift`, `UI/DisplayModes.swift`, `RemoteServer.swift:233-235`, `AgentController.swift:403`, `ToolboxModel.swift:160-171,532-537`

**Interfaces (produces):**
```swift
struct MetricsFrame: Equatable {
    var snap = MetricsSnapshot()
    var cpu: [Double] = [], gpu: [Double] = [], mem: [Double] = [], netRx: [Double] = [], netTx: [Double] = []
}
@MainActor final class SystemMetrics: ObservableObject {
    @Published private(set) var frame = MetricsFrame()
    var snap: MetricsSnapshot { frame.snap }               // compatibility accessors
    var cpuHistory: [Double] { frame.cpu } // …gpuHistory, memHistory, netRxHistory, netTxHistory
    enum Cadence: TimeInterval { case fast = 2, slow = 6 }
    func start(); func stop(); func setCadence(_ c: Cadence)
}
/// Runs off the main actor; owns the delta state and cached IOKit services.
final class MetricsSampler: @unchecked Sendable { func sample() -> MetricsSnapshot }
```
- [ ] **Step 1:** move the six `sample*` functions into `MetricsSampler` (nonisolated); cache `IOServiceGetMatchingService(AppleSmartBattery)` and the IOAccelerator iterator's first matching service id (re-match only if a read fails).
- [ ] **Step 2:** `SystemMetrics.tick()` → `Task.detached(priority: .utility) { sampler.sample() }` then on main build the new frame (append + trim histories) and assign `frame` once. Timer tolerance 0.5 s. `setCadence` re-creates the timer only if the interval changed.
- [ ] **Step 3:** `ToolboxModel`: `setCadence(.fast)` when `displayMode == .full && route == .dashboard`, `.slow` otherwise (hook `route.didSet` and `setDisplay`).
- [ ] **Step 4:** build; the dashboard still renders (`XENEON_RENDER`).

### Task 9: Gesture state split + observation scoping

**Files:**
- Create: `Sources/XeneonToolbox/PanelGestures.swift`
- Modify: `ToolboxModel.swift` (move `pullFrac`, `controlExt`, `deckLongPressAt` writes to `gestures.*`), `UI/PanelView.swift` (RootView: `let metrics`, overlays become `ControlCenterHost`/`ShadePullHost` observing `gestures`), `UI/DeckView.swift:70-80` (observe `model.gestures`), `UI/DashboardView.swift` (`let model`), `UI/PanelView.swift` NavRail (badge + dot as leaf views)

**Interfaces (produces):**
```swift
@MainActor final class PanelGestures: ObservableObject {
    @Published var pullFrac: Double?
    @Published var controlExt: Double = 0
    @Published var longPressAt: CGPoint?      // driver long-press, Edge-local coords (deck tiles, dashboard board, dock icons)
}
// ToolboxModel: let gestures = PanelGestures()   (old properties removed); setDeckLongPress(_:) renamed setLongPressEnabled(_:)
private struct ControlCenterHost: View { @ObservedObject var gestures: PanelGestures; let model: ToolboxModel … }
private struct ShadePullHost: View { @ObservedObject var gestures: PanelGestures; let metrics: SystemMetrics; let model: ToolboxModel … }
private struct TasksBadge: View { @ObservedObject var todos: TodoStore … }     // count + urgent
private struct FocusDot: View { @ObservedObject var timer: FocusTimer … }
```
- [ ] **Step 1:** create `PanelGestures`; replace every `controlExt`/`pullFrac`/`deckLongPressAt` read/write (grep) with `gestures.controlExt` / `gestures.pullFrac` / `gestures.longPressAt`. `closeControlCenter`, `handleControlPull`, `handleShadePull`, `handleBottomPull`, `commit(to:)`, `handleLongPress` write `gestures.*` inside the same `withAnimation` blocks.
- [ ] **Step 2:** `RootView`: `@ObservedObject var model` stays; `var metrics: SystemMetrics` (no wrapper); the control-centre and shade overlays move into the two host views.
- [ ] **Step 3:** `DashboardView`: `let model: ToolboxModel` (not observed); anything it needs live comes from `metrics`, `weather`, `layout`, or tile-level observation.
- [ ] **Step 4:** `NavRail`: `let todos`, `let focusTimer`; badge/dot rendered by `TasksBadge`/`FocusDot`.
- [ ] **Step 5:** build + render dashboard/minimal; pull-gesture overlay still works (env `XENEON_SHADE=0.5` render shows the shade at half).

### Task 10: Event-driven media

**Files:**
- Modify: `Sources/XeneonToolbox/MediaController.swift`

- [ ] **Step 1:** `start()` subscribes `DistributedNotificationCenter.default()` to `com.spotify.client.PlaybackStateChanged` and `com.apple.Music.playerInfo` (both → `refresh()`), and `NSWorkspace` `didLaunchApplicationNotification`/`didTerminateApplicationNotification` (→ `refresh()`; termination of the last player → `nowPlaying = nil`). Safety poll: a 20 s timer created only while `playerRunning` (checked in `refresh()`), invalidated otherwise.
- [ ] **Step 2:** `apply(_:)` assigns `nowPlaying` only when `np != nowPlaying || abs(np.elapsedNow() - (nowPlaying?.elapsedNow() ?? -1)) > 2` (drift correction) so the 20 s poll doesn't publish unchanged values.
- [ ] **Step 3:** `stop()` (new) tears down; `ToolboxModel.setDisplay(.sleep)` calls `media.stop()`, other modes `media.start()`.
- [ ] **Step 4:** build; run the dev build 60 s with Spotify paused and confirm with `ps -ax | grep -c osascript` sampled every 5 s that no `osascript` appears; play/pause in Spotify and confirm the render/state updates within 1 s (`curl /api/state` on the dev build's port, which is 8766+ while the installed app holds 8765; the dev build's URL is printed on stderr with its token).

### Task 11: Rendering discipline — shadows on shapes, glow strokes, drawing groups, clock cadence

**Files:**
- Modify: `UI/Components.swift` (`TileSurface`, `RingGauge`, `Sparkline`, `CapacityBar`), `UI/Tiles.swift` (`ClockTile`), `UI/ClockAppView.swift` (`NowCard`, `WorldRow`), `UI/DisplayModes.swift` (`MinimalView.clockBlock`), `UI/NowPlayingView.swift` (`ScrubBar` 0.5 s → 1 s), `AppDelegate.swift:265` (yield timer 1 s → 2 s)

- [ ] **Step 1:** `TileSurface`: build the background as a `ZStack` of shapes and apply `.shadow(color: .black.opacity(0.45), radius: 18, y: 12)` to that background shape only (remove the trailing `.shadow` on the content). Keep the sheen/stroke.
- [ ] **Step 2:** `RingGauge`: replace `.shadow(color: color.opacity(0.55), radius: 7)` with an underlying `Circle().trim(...).stroke(color.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth + 10, lineCap: .round))` (same rotation/animation). `Sparkline`: replace `.deckGlow` with a second stroke `lineWidth: 7, color.opacity(0.18)` under the line and wrap the ZStack in `.drawingGroup()`. `CapacityBar`: drop `.deckGlow`, add an inner highlight `Capsule().fill(.white.opacity(0.18)).frame(height: 2)` aligned top.
- [ ] **Step 3:** Clock cadence: `ClockTile` → `TimelineView(.everyMinute)`, no seconds. `NowCard` → `.everyMinute` for HH:MM/date/progress; seconds in a nested `TimelineView(.periodic(from: .now, by: 1))` wrapping only the seconds `Text`, `.frame(width: 76, alignment: .leading)`. `WorldRow` and `MinimalView.clockBlock` → `.everyMinute`. `ScrubBar` → `by: 1`.
- [ ] **Step 4:** yield timer interval 2.0 s.
- [ ] **Step 5:** build; render dashboard/clock/minimal; measure CPU on dashboard and ambient exactly as in Task 0 and add an interim row to `measurements.md`.

---

## Phase 4 — Dashboard grid, rail, depth

### Task 12: `GridPacker` (ToolboxKit, tested) + `DashboardLayout` v2

**Files:**
- Create: `Sources/ToolboxKit/GridPacker.swift`, `Tests/ToolboxKitTests/GridPackerTests.swift`
- Modify: `Sources/XeneonToolbox/DashboardLayout.swift` (rewrite)

**Interfaces (produces):**
```swift
// ToolboxKit
public struct GridSlot: Equatable, Sendable { public let column: Int, row: Int, columns: Int, rows: Int }
public struct GridItem<ID: Hashable & Sendable>: Sendable { public let id: ID; public let columns: Int; public let rows: Int; public init(id:columns:rows:) }
public enum GridPacker {
    /// First-fit, left-to-right, top row first. Items that don't fit in `columns`×`rows` land in `overflow` (order kept).
    public static func pack<ID>(_ items: [GridItem<ID>], columns: Int, rows: Int) -> (placed: [ID: GridSlot], overflow: [ID])
}
// app
enum DashTile: String, CaseIterable, Codable, Identifiable { case clock, cpu, gpu, memory, network, storage, power, upNext, tasks, thermals, dock, clipboard, nowPlaying
    var title: String; var icon: String; var sizes: [TileSize]; var defaultSize: TileSize }
enum TileSize: String, Codable, CaseIterable { case s, w, t, l; var columns: Int { self == .w || self == .l ? 2 : 1 }; var rows: Int { self == .t || self == .l ? 2 : 1 }; var label: String }
struct PlacedTile: Codable, Equatable, Identifiable { var id: DashTile { tile }; let tile: DashTile; var size: TileSize }
@MainActor final class DashboardLayout: ObservableObject {
    static let columns = 8, rows = 2, capacity = 16
    @Published private(set) var board: [PlacedTile]
    var slots: [DashTile: GridSlot]; var overflow: [DashTile]; var available: [DashTile]  // not on the board
    var cellsUsed: Int
    func move(_ tile: DashTile, toward target: DashTile, before: Bool)
    func remove(_ tile: DashTile); func add(_ tile: DashTile, size: TileSize) -> Bool; func setSize(_ tile: DashTile, _ size: TileSize) -> Bool
    func reset(); func save()
}
```
Default board: clock T, cpu S, gpu S, memory S, network W, storage S, power S, upNext W, tasks S, thermals S, dock W, nowPlaying S (16 cells). Migration from `dashboard.layout.v1`: keep the saved order for known tiles at their default sizes, drop `controls`, append the new tiles; save as `dashboard.layout.v2`.

- [ ] **Step 1: Tests**:
```swift
import XCTest
@testable import ToolboxKit
final class GridPackerTests: XCTestCase {
    func testTallTileTakesBothRowsAndNextTilesFlowRight() {
        let r = GridPacker.pack([GridItem(id: "clock", columns: 1, rows: 2), GridItem(id: "cpu", columns: 1, rows: 1), GridItem(id: "gpu", columns: 1, rows: 1)], columns: 8, rows: 2)
        XCTAssertEqual(r.placed["clock"], GridSlot(column: 0, row: 0, columns: 1, rows: 2))
        XCTAssertEqual(r.placed["cpu"], GridSlot(column: 1, row: 0, columns: 1, rows: 1))
        XCTAssertEqual(r.placed["gpu"], GridSlot(column: 2, row: 0, columns: 1, rows: 1))
    }
    func testWideTileSkipsAColumnItCannotFit() {
        // 7 singles on the top row leave one free column; a wide tile must go to row 1.
        var items = (0..<7).map { GridItem(id: "s\($0)", columns: 1, rows: 1) }
        items.append(GridItem(id: "wide", columns: 2, rows: 1))
        let r = GridPacker.pack(items, columns: 8, rows: 2)
        XCTAssertEqual(r.placed["wide"], GridSlot(column: 0, row: 1, columns: 2, rows: 1))
    }
    func testOverflowKeepsOrder() {
        let items = (0..<18).map { GridItem(id: $0, columns: 1, rows: 1) }
        let r = GridPacker.pack(items, columns: 8, rows: 2)
        XCTAssertEqual(r.placed.count, 16); XCTAssertEqual(r.overflow, [16, 17])
    }
    func testDefaultBoardFillsExactlySixteenCells() {
        let items = [GridItem(id: "clock", columns: 1, rows: 2), GridItem(id: "cpu", columns: 1, rows: 1), GridItem(id: "gpu", columns: 1, rows: 1), GridItem(id: "memory", columns: 1, rows: 1), GridItem(id: "network", columns: 2, rows: 1), GridItem(id: "storage", columns: 1, rows: 1), GridItem(id: "power", columns: 1, rows: 1), GridItem(id: "upNext", columns: 2, rows: 1), GridItem(id: "tasks", columns: 1, rows: 1), GridItem(id: "thermals", columns: 1, rows: 1), GridItem(id: "dock", columns: 2, rows: 1), GridItem(id: "nowPlaying", columns: 1, rows: 1)]
        let r = GridPacker.pack(items, columns: 8, rows: 2)
        XCTAssertTrue(r.overflow.isEmpty)
        XCTAssertEqual(r.placed.values.reduce(0) { $0 + $1.columns * $1.rows }, 16)
    }
}
```
- [ ] **Step 2:** run → compile failure. **Step 3:** implement the packer with an occupancy `[[Bool]]` scanning `row in 0..<rows`, `column in 0..<columns` for each item in order (a fit requires every cell of the footprint free and inside the grid). **Step 4:** tests PASS. **Step 5:** rewrite `DashboardLayout` per the interface (packing recomputed in `didSet` of `board`); build.

### Task 13: `DashboardGridView` — placed tiles, 2-D reorder, resize, remove, gallery

**Files:**
- Rewrite: `Sources/XeneonToolbox/UI/DashboardView.swift`
- Create: `Sources/XeneonToolbox/UI/TileGalleryOverlay.swift`
- Modify: `Sources/XeneonToolbox/UI/Tiles.swift` (tiles accept `size: TileSize` where their layout differs; `ControlsTile` deleted; `ToggleDot` kept), `ToolboxModel.swift` (`setLongPressEnabled(_:)` is turned on while the dashboard is on screen and not editing; the driver point arrives in `gestures.longPressAt`)

**Interfaces (produces):**
```swift
struct DashboardView: View { let model: ToolboxModel; @ObservedObject var metrics: SystemMetrics; @ObservedObject var weather: WeatherService; @ObservedObject var layout: DashboardLayout }
// Tile content resolver
@ViewBuilder func tileContent(_ tile: DashTile, size: TileSize) -> some View
struct TileGalleryOverlay: View { @ObservedObject var layout: DashboardLayout; var onClose: () -> Void }
```
- [ ] **Step 1:** geometry: inside a `GeometryReader`, `gap = 16`, `cellW = (w - 7*gap)/8`, `cellH = (h - gap)/2`; each placed tile gets `.frame(width: cellW*cols + gap*(cols-1), height: cellH*rows + gap*(rows-1))` and `.position(x:y:)` from its `GridSlot`. Overflow tiles are not drawn; edit mode shows "N tiles don't fit — remove or shrink one" in the bottom bar.
- [ ] **Step 2:** edit mode: enter via long-press anywhere on the board (`model.setLongPressEnabled(true)` while the dashboard is on screen and not editing; `gestures.longPressAt` inside the board and outside any Dock icon enters edit mode), or from the rail's "⋯" sheet ("Edit dashboard"). While editing: `model.setReorderDragging(true)`; a `DragGesture(minimumDistance: 6)` on the board picks the tile whose frame contains `startLocation`, floats a copy at the finger, and calls `layout.move(d, toward: target, before: center.x < targetFrame.midX)` when the dragged centre enters another tile's frame; ⊖ badge → `layout.remove`; a size badge (bottom-trailing, label "S/W/T") cycles `tile.sizes` via `layout.setSize` (shows a brief "Doesn't fit" toast when it returns false); an **Add** tile (dashed) → `TileGalleryOverlay`; bottom bar: "N of 16 cells" + Reset + Done.
- [ ] **Step 3:** `TileGalleryOverlay`: `ModalScaffold` card listing `layout.available` tiles as rows (icon, title, one-line description, size chips for `tile.sizes`, "Add" adds at the chosen size and closes; disabled with "No room" when `cellsUsed + size.cells > 16`).
- [ ] **Step 4:** detail modals (CPU/GPU/Memory/Network/Weather/Energy) unchanged; `.expandable` taps remain on the non-edit tiles.
- [ ] **Step 5:** render: `XENEON_RENDER` dashboard (normal), `XENEON_EDIT=1` (edit mode), and `XENEON_GALLERY=1` (gallery) → view PNGs and iterate until the layout is clean (no clipped text, header baselines aligned, gaps consistent).

### Task 14: Compact rail with big targets + "⋯" sheet

**Files:**
- Modify: `Sources/XeneonToolbox/UI/PanelView.swift` (`NavRail`, `NavButton`), create `Sources/XeneonToolbox/UI/RailMenu.swift`

- [ ] **Step 1:** `NavRail` width 112; brand mark reduced to the grid glyph (28 pt) with "XT" wordmark hidden; nav items: `VStack(spacing: 6)` of `NavButton` sized 88×76 (`Image` 24 pt bold + `Text(title).font(.deck(12, .semibold))`), active state = accent-tinted rounded rect (radius 18) + accent glyph; bottom cluster: touch dot button (88×56: dot + "Touch"; tap → `model.toggleTouch()`), "⋯" button (88×64) → `model.showRailMenu = true`.
- [ ] **Step 2:** `RailMenu`: `ModalScaffold` anchored bottom-leading (offset from the rail) with six 300×64 rows: Full screen, Ambient, Sleep, Hide to badge, Edit dashboard (only on the dashboard route), Settings, Quit (red text).
- [ ] **Step 3:** render dashboard + deck to confirm the content width increase and that the rail reads well; check every target ≥ 44 pt by inspecting the frame constants.

### Task 15: Theme v2 depth pass + pressure semantics + numeric transitions

**Files:**
- Modify: `UI/DesignSystem.swift` (tokens + helpers), `UI/Components.swift` (`TileSurface` inner highlight/well, `TileHeader`), `UI/Tiles.swift` (all metric tiles), `UI/DisplayModes.swift` (`MinimalView` type scale), `UI/PanelView.swift` (`DeckBackground` wash)

**Interfaces (produces):**
```swift
extension Theme {
    static let wellFill = Color.black.opacity(0.22)          // recessed graph/gauge area
    static let innerHighlight = Color.white.opacity(0.06)    // 1 px top highlight on surfaces
    static func pressure(_ fraction: Double, base: Color) -> Color   // ≥0.9 critical, ≥0.75 warning, else base
}
extension View { func numeric() -> some View }   // .contentTransition(.numericText()) + .animation(Motion.smooth) on the value
struct Well<Content: View>: View                  // RoundedRectangle(14) wellFill + content, used by sparklines/rings
```
- [ ] **Step 1:** tokens + helpers; `TileSurface` gets the inner highlight line (already partially there — keep one) and the `Well` container; `TileHeader` unchanged.
- [ ] **Step 2:** metric tiles: CPU/GPU/Memory readouts use `.numeric()`; CPU/Memory/Storage/Thermals tint via `Theme.pressure`; S-size tiles put the sparkline inside a `Well` (height 56); W-size CPU/Network variants show a larger graph (the ring left, graph right).
- [ ] **Step 3:** `MinimalView` uses the locked scale (readout 176 → keep, secondary 27 → 24, vitals 42 → 40) and the same pressure tints.
- [ ] **Step 4:** render dashboard + minimal; compare against the "before" PNGs side by side.

### Task 16: Now Playing tile + ambient bar cleanup

**Files:**
- Create: `Sources/XeneonToolbox/UI/NowPlayingTile.swift`
- Modify: `UI/DashboardView.swift` (bottom bar removed), `UI/ControlCenterView.swift` (keep compact bar), `ToolboxModel.swift` (`showNowPlaying` now only affects the ambient bar), `UI/SettingsView.swift` (toggle copy: "Show Now Playing on the ambient screen")

- [ ] **Step 1:** `NowPlayingTile(media:onExpand:)` S: artwork 96 pt, title/artist, compact transport row; W: artwork 140 pt + scrub bar. Empty state (nothing playing): "Nothing playing" + "Open Music / Spotify" buttons that launch via `NSWorkspace.shared.openApplication`.
- [ ] **Step 2:** remove the dashboard bottom bar code paths; build; render with `XENEON_RENDER` while Spotify is paused on a track to see the populated tile.

---

## Phase 5 — Gadgets

### Task 17: Up Next tile

**Files:**
- Create: `Sources/XeneonToolbox/UI/UpNextTile.swift`
- Modify: `Metrics/CalendarService.swift` (expose `upcoming: [Event]` = today's events not past, max 3), `UI/DashboardView.swift` (case `.upNext` → tile; tap → `model.showAgenda = true`)

- [ ] **Step 1:** `UpNextTile(calendar: CalendarService, size:)` observes the service; rows: 5 pt calendar-colour bar, title (deck 15 semibold, 1 line), time (readout 14) or "Now" in the colour; W shows 3 rows, S shows 2; empty: "Nothing else today" / no access: "Allow Calendar access" (opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`).
- [ ] **Step 2:** build + render (`XENEON_AGENDA=1` injects mock events).

### Task 18: Tasks tile

**Files:**
- Create: `Sources/XeneonToolbox/UI/TasksTile.swift`
- Modify: `UI/DashboardView.swift` (case `.tasks`; header tap → `model.route = .tasks`)

- [ ] **Step 1:** `TasksTile(todos: TodoStore, size:)`: header with counts pill ("2 overdue" red / "3 today" amber / "All clear" green); up to 3 (S) or 6 (W) open items sorted by `todos.sorted`, each with a 44 pt checkbox (`todos.toggle(id)`) and due chip; empty state "Nothing on your list".
- [ ] **Step 2:** add `XENEON_TODOS_DEMO=1` handling in `TodoStore.init` (three in-memory sample items: one overdue, one due today, one anytime; never saved) mirroring `XENEON_AGENDA`; build + render the dashboard with it set.

### Task 19: `SMCReader` + `ThermalSnapshot` + Thermals tile

**Files:**
- Create: `Sources/XeneonToolbox/Metrics/SMCReader.swift`, `Sources/XeneonToolbox/UI/ThermalsTile.swift`
- Modify: `Metrics/SystemMetrics.swift` (thermals in the frame every 3rd tick), `UI/DashboardView.swift` (case `.thermals`), `AgentController.swift` (`get_app_state` appends `soc=62°C fan=1800rpm` when available)

**Interfaces (produces):**
```swift
struct ThermalSnapshot: Equatable { var socC: Double?; var gpuC: Double?; var fanRPM: [Double] }
final class SMCReader: @unchecked Sendable {
    init?()                                  // IOServiceOpen("AppleSMC"); nil when unavailable
    func readFloat(_ key: String) -> Double?  // "flt " keys; sp78/ui8/ui16 converted
    func keys(prefix: String) -> [String]     // enumerated once (#KEY + kSMCGetKeyFromIndex=8), cached
    func thermals() -> ThermalSnapshot        // soc = max of keys with prefix Tp/Tc/Te (fallback: any T* < 130), gpu = max Tg*, fans = F{i}Ac for i < FNum
}
```
SMC protocol: selector 2 (`kSMCHandleYPCEvent`), 80-byte struct: key@0 (fourcc, host-endian), keyInfo.dataSize@28, dataType@32, result@40, data8@42 (9 = key info, 5 = read, 8 = key by index), data32@44 (index), bytes@48.

- [ ] **Step 1:** implement `SMCReader` (port the verified scratch code from `<scratchpad>/smc2.swift`); the temperature key set is chosen once at init (keys with prefixes `Tp`, `Tc`, `Te`, `Tg` whose first read is in 5…130 °C) and re-read each tick; limit to 24 keys for CPU and 16 for GPU (the hottest at init).
- [ ] **Step 2:** add `var thermals: ThermalSnapshot? = nil` to `MetricsSnapshot`; `MetricsSampler` owns an optional `SMCReader` and fills `thermals` every 3rd sample (carrying the previous value in between).
- [ ] **Step 3:** `ThermalsTile`: S: ring gauge of SoC °C (scale 0…110, `Theme.pressure(t/110)`), GPU °C secondary readout, fan RPM row ("2 fans · 2080 rpm") when `fanRPM` non-empty; "unavailable" state when `socC == nil`.
- [ ] **Step 4:** build + render; confirm the values match `./smc2` output within a few degrees.

### Task 20: Dock tile

**Files:**
- Create: `Sources/XeneonToolbox/RunningAppsMonitor.swift`, `Sources/XeneonToolbox/UI/DockTile.swift`
- Modify: `UI/DashboardView.swift` (case `.dock`), `ToolboxModel.swift` (`let runningApps = RunningAppsMonitor()`)

**Interfaces (produces):**
```swift
@MainActor final class RunningAppsMonitor: ObservableObject {
    struct App: Identifiable, Equatable { let id: pid_t; let name: String; let path: String; let icon: NSImage; let isActive: Bool }
    @Published private(set) var apps: [App]     // regular activation policy, sorted by launch order; the Toolbox itself excluded
    func start()                                 // NSWorkspace didLaunch/didTerminate/didActivate notifications → refresh()
    func activate(_ app: App)                    // WindowMover.openOffEdge(appPath:)
}
```
- [ ] **Step 1:** monitor per interface (icons via `NSWorkspace.shared.icon(forFile:)` sized 64, cached by path in the existing `DeckIconCache`-style NSCache).
- [ ] **Step 2:** `DockTile(monitor:size:)`: W shows up to 10 icons (56 pt, 12 pt gap) in one row with the active app underlined by an accent dot; S shows 4; overflow "+N". Tap → `activate`. Long-press (`gestures.longPressAt` inside an icon's global frame, collected with a preference key like the deck) → `DashboardView` shows `ScreenPickerOverlay(action: DeckAction.app(path: app.path), …)`. Prerequisite: extract the deck's `screenPicker(_:)` and its row helpers from `DeckView.swift` into `Sources/XeneonToolbox/UI/ScreenPickerOverlay.swift` as `struct ScreenPickerOverlay: View { let model: ToolboxModel; let deck: DeckStore; let action: DeckAction; let running: Bool; let onClose: () -> Void }` (DeckView keeps its behaviour by using it).
- [ ] **Step 3:** build + render.

### Task 21: Clipboard tile

**Files:**
- Create: `Sources/ToolboxKit/ClipboardHistory.swift`, `Tests/ToolboxKitTests/ClipboardHistoryTests.swift`, `Sources/XeneonToolbox/ClipboardStore.swift`, `Sources/XeneonToolbox/UI/ClipboardTile.swift`
- Modify: `ToolboxModel.swift` (`let clipboard = ClipboardStore()`, started in `onAppear`, paused in sleep), `UI/DashboardView.swift` (case `.clipboard`)

**Interfaces (produces):**
```swift
// ToolboxKit (pure)
public struct ClipboardHistory: Equatable, Sendable {
    public private(set) var items: [String] = []
    public let capacity: Int
    public init(capacity: Int = 6)
    /// Newest first; a repeat of an existing entry moves it to the front; whitespace-only text is ignored.
    public mutating func push(_ text: String)
    public mutating func remove(at index: Int)
}
// app
@MainActor final class ClipboardStore: ObservableObject {
    @Published private(set) var history = ClipboardHistory()
    @Published var paused = false
    func start(); func stop()                  // 1 s timer comparing NSPasteboard.general.changeCount; reads the string only on change
    func copyBack(_ text: String)             // sets the pasteboard and remembers the resulting changeCount so it isn't re-recorded
    func remove(at: Int)
}
```
- [ ] **Step 1: Tests**:
```swift
final class ClipboardHistoryTests: XCTestCase {
    func testNewestFirstAndCapacity() {
        var h = ClipboardHistory(capacity: 3)
        ["a", "b", "c", "d"].forEach { h.push($0) }
        XCTAssertEqual(h.items, ["d", "c", "b"])
    }
    func testRepeatMovesToFront() {
        var h = ClipboardHistory(); ["a", "b", "a"].forEach { h.push($0) }
        XCTAssertEqual(h.items, ["a", "b"])
    }
    func testIgnoresBlank() { var h = ClipboardHistory(); h.push("  \n"); XCTAssertTrue(h.items.isEmpty) }
}
```
- [ ] **Step 2:** run → fail; **Step 3:** implement; **Step 4:** PASS. **Step 5:** `ClipboardStore` + `ClipboardTile` (rows: first line of the clip, 1 line, monospaced for code-looking text; tap → `copyBack` with a 1 s "Copied" flash; ⓧ → remove; header shows a pause/play glyph). Build + render.

### Task 22: Network detail rows (SSID, local IP, public IP)

**Files:**
- Modify: `Metrics/SystemMetrics.swift` (`MetricsSnapshot.localIPv4: String?` from `getifaddrs` AF_INET on the interface with the most bytes), `UI/MetricDetail.swift` (network detail: a right column with rows Wi-Fi (from `SystemToggles.wifiName` via a fresh `Self.currentSSID()` call on open), Local IP, Public IP), create `Metrics/PublicIP.swift` (`actor PublicIP { static func fetch() async -> String? }` via `https://api.ipify.org?format=json`, cached 1 h)

- [ ] **Step 1:** implement; the detail view loads the public IP with `.task` when opened. **Step 2:** build + render with `XENEON_DETAIL=network`.

---

## Phase 6 — Verification and docs

### Task 23: Full verification, measurements, README, screenshots

- [ ] **Step 1:** `swift build -c release 2>&1 | tail -3`, `swift test 2>&1 | tail -5` — all green.
- [ ] **Step 2:** CPU "after" rows (dashboard + ambient) with the exact Task 0 commands; the plan's targets are ≤ 8% and ≤ 3%. If a target is missed, sample again (`sample <pid> 5`) and fix the top offender before moving on.
- [ ] **Step 3:** Renders for README: `dashboard.png`, `customize.png` (edit mode), `minimal.png`, `clock.png`, `settings.png` via `XENEON_RENDER` at scale 1 into `docs/img/`; the resolution guide as a new `docs/img/resolution.png`.
- [ ] **Step 4:** README: Highlights bullet for the dashboard (grid, tiles, gallery), a "Resolution" note under "How touch works"/setup ("If macOS picks 1920×1080 the Toolbox offers a one-tap fix"), touch reliability sentence, the CLI `display-modes`/`set-mode` rows; remove the Configs-tile mention in "Make it yours".
- [ ] **Step 5:** `git status` review of every changed file; summarize for the user with the before/after table and the PNGs.


---

## Restyle (2026-09-18)

"Obsidian Instrument": carbon glass tiles with a lit top edge and dark bottom
edge (`bezel`), bone text, one amber signature (index bar on the rail, primary
buttons, the focus ring), ice as the secondary hue and hue-coded instruments.
Tick-ring gauges replace the stroked arcs (48 ticks over 270°, lit ticks masked
by an animated `strokeEnd` on the render server). Sentence-case labels replace
the tracked uppercase eyebrows; SF Mono carries every numeral and the hero
clocks. Shared `PrimaryButton` / `GhostButton` / `CircleIconButton` and one
modal shell across the deck, chat, tasks, settings and every detail card.
New tiles: Focus, World clocks, Weather (hourly), Devices (Bluetooth charge via
`BluetoothReport`, tested) and Quick actions. Render hooks: `XENEON_BOARD`,
`XENEON_WEATHER_DEMO`, `XENEON_REMOTE_DEMO` (placeholder access key in
screenshots; Settings also gained "New link" to rotate the key).

## Follow-ups (2026-09-18)

- **Pointer return.** Root cause: the driver parked the pointer at the Edge's
  bottom-right pixel after every tap, scroll and momentum coast, so a touch
  stranded the cursor away from the display the user was working on.
  `CursorReturn` (XeneonTouchCore, tested) remembers the pointer at first
  contact and the driver posts a tagged move back once the gesture and any
  coasting end; a real mouse move mid-gesture (relayed by `CursorController`)
  cancels the return.
- **Weather modal** relaid as two columns (1240×470): close button in the header
  row, hourly strip in a well, week below.
- **Permissions.** `AppPermission` (status, system request, exact Settings pane)
  plus `PermissionGuide` cards and a Settings hub that poll status every second
  and confirm on their own.
- **Updater.** Background staging (download to Application Support, sha256,
  version, codesign --deep, spctl, team), install when idle
  (`UpdateStrategy.isQuietMoment`, tested) or at quit, rollback-safe swap
  helper keeping `.previous`, quiet toasts, "what's new" after relaunch,
  policies Automatic / Ask first / Off, ETag-conditional checks with jitter.

- **Stale permission grants.** Root cause of "Calendar shows allowed but the
  app keeps asking": TCC keys a grant to the code signature, and the bundle
  went from ad-hoc to Developer ID signing, so requests were refused instantly
  without a prompt while the status stayed "not determined".
  `AppPermission.requestRepairingStaleGrant` detects the instant refusal, runs
  `tccutil reset <service> <bundle>` and asks again; the calendar service uses
  the same path at launch.
- **Boost.** `BoostScanner` (regular apps + one `ps` pass) and `BoostView`:
  heavy background apps pre-selected, graceful `terminate()`, freed-memory
  report. Reachable from More, the Quick actions tile and as a Deck action.
- **Now Playing tile** redrawn as an album card: artwork bleeds to the tile
  edges under a gradient, transport with an amber play key.
- Version 1.18.0.

## Outcome (2026-09-17)

All tasks executed in this session. Deviations from the plan, with reasons:

- **Task 11/15**: numeric `contentTransition` on readouts was dropped — every SwiftUI animation frame forces a full-tree layout under `NSHostingView`, which is exactly what made the dashboard expensive. For the same reason the ring and capacity-bar animations moved onto Core Animation layers (`UI/LayerGauges.swift`); `ImageRenderer` exports use the static SwiftUI shapes via the `renderStatic` environment key. `NSHostingView.sizingOptions = []` also removed the per-frame min/max size passes.
- **Task 12**: the packer's item type is `PackedItem` (not `GridItem`, which clashes with SwiftUI in files that import both).
- **Task 13/20**: the dashboard and the Running-apps tile share `ScreenPickerOverlay`, extracted from `DeckView`.
- **Task 22**: the local IP prefers the busiest physical (`en*`) interface over VPN tunnels.
- Dev hooks added for measurement and screenshots: `XENEON_DEV_FRAME` (place a borderless dev window), `XENEON_NO_TOUCH`, `XENEON_DEMO_TOUCH`, `XENEON_CALENDAR_DEMO`, `XENEON_TODOS_DEMO`, `XENEON_EDIT`, `XENEON_GALLERY`, `XENEON_RESOLUTION_DEMO`.

Measurements: `docs/superpowers/plans/measurements.md`.
