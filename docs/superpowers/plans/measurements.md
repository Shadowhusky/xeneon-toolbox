# Measurements

Dev build, devMode window 1900×720 on the main display, `top -l 6 -s 3`, median of samples 2–6.

| Stage | Dashboard (full) | Ambient (minimal) |
| --- | --- | --- |
| Before (baseline, Task 0) | 42.8% | 1.9% |
| After observation split, metrics frame, media events, shadows on shapes | 27.3% | 0.3% |
| + linear ring gradient, generic footer, minute uptime | 23.0% | 0.4% |
| + hosting view `sizingOptions = []` | 25.0% | — |
| + gauge animations off (diagnostic only) | 3.2% | — |
| + rings and bars animated on CA layers (Task 11 final) | 2.4% | 0.3% |
| **After the grid redesign + gadgets (final, Task 23)** | **1.7%** | **0.2%** |

## Live resolution switch (Task 7, 2026-09-17 17:40)

`xeneon-touch set-mode 26` → Edge reported 1920 × 1080 (native=false); `set-mode 28` → 2560 × 720 (native=true), bounds unchanged (187,1080). The installed v1.17.0 app logged `digitizer lost → seize OK` with no `digitizer connected` while at 1920 × 1080 (its geometry lookup found no display), then `Edge display appeared ×3 → digitizer connected` after the restore — the pre-fix failure mode, reproduced.

## Media polling (Task 10)

Dev build idle on the dashboard for 40 s with Spotify running (paused): 0 `osascript` child processes seen across 8 samples (the old poller spawned one every 2 s).
