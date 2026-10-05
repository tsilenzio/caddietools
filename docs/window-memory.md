# Window memory and restore

Last Updated: 2026-10-04

Status markers are defined in the last section. This document records the intended behavior for remembering a window's frame before tiling and restoring it later. It covers the green button, title-bar double-clicks, the Ctrl+Opt+Cmd tiling hotkeys, and edge-drag snapping (`edge-drag.md`). Statements marked **Candidate** are interpretations or design proposals made in that discussion and not yet confirmed.

## Terms

- **Natural frame**: the size and position the owner gave a window by hand, before any tiling. Called `original` in the design below.
- **Managed frame**: the last frame this system set on the window. Called `applied`.
- **Tiled**: placed by a tiling hotkey (halves, quarters, thirds, two thirds) or, later, by an edge drag.
- **Maximized**: placed on the full usable frame of its screen, the area below the menu bar and above the Dock, by Ctrl+Opt+Cmd+Enter or the green button. A maximized window is a tiled window whose tile is the whole screen.
- **Restore**: putting a tiled window back to its natural frame.

## Why this exists

The green button originally ran macOS **Window > Fill**, which knows nothing about this system's tiling. After Ctrl+Opt+Cmd+Enter, clicking the green button re-filled a window that was already maximized. Before the per-side gap rule, the hotkey left a 1 pt border on every side and Fill did not, so the click grew the window by 1 pt in each direction. That registered as a resize where the owner expected a restore, and nothing could return the window to its size from before the hotkey. **Owner requirement**: macOS behaves the way Windows does here.

## Green button

1. **Owner requirement**: clicking the green button on a maximized window restores it to its natural frame, size and position.
2. **Owner requirement**: this works with Ctrl+Opt+Cmd+Enter. Pressing the hotkey and then clicking the green button undoes the hotkey and returns the window to how it was before the hotkey was ever pressed.
3. **Owner agreed**: clicking the green button on a window that is not maximized maximizes it using this system's own maximize, not macOS Fill. The button and the hotkey produce the same frame, including the no-gap rule and per-app presets such as Terminal's 60% by 70%.
4. **Owner requirement**: clicking the green button on an already maximized window never produces a resize. That case is a restore.
5. **Candidate**: on a window tiled to a half, third, or quarter, the green button maximizes it, matching Windows, and the natural frame from before the first tile is kept.
6. **Owner requirement**, unchanged from TKT-001: Option-click enters real macOS full screen, and hovering the button simulates Option so its menu shows the Option items.

## Title-bar double-click

29. **Owner requirement** (TKT-037): double-clicking a window's title bar maximizes and restores exactly as the green button does, in place of the system's own double-click action (`AppleActionOnDoubleClick`, which was `Fill` on the owner's machine).
30. A double-click counts as a title-bar double-click when its second click lands in the top 40 pt of the window under the cursor, on window chrome rather than a control. Roles counted as chrome: `AXWindow`, `AXToolbar`, `AXTabGroup`, `AXGroup`, `AXStaticText`, `AXImage`. Roles such as `AXButton`, `AXRadioButton` (tabs in native tab bars), `AXTextField`, and `AXPopUpButton` are left to the app. The band and roles come from Accessibility probes of Chrome, Ghostty, and Code windows, where those apps' title areas fill the top 40 pt and content or toolbar controls begin below it.
31. Known limit: Chrome reports its tabs as `AXGroup`, the same as the empty tab strip, so double-clicking a Chrome tab also toggles. The setting `TitleBarTweaks.titleBarDoubleClick = false` turns the feature off.

## Tiling hotkeys and the natural frame

7. **Owner requirement**: every tiling hotkey (arrows, U I J K, D F G, E R T, Enter) remembers the window's natural frame from before any tiling.
8. **Owner requirement**: a chain of tiles keeps the first natural frame. For the sequence natural → Ctrl+Opt+Cmd+Left → Ctrl+Opt+Cmd+Right → Ctrl+Opt+Cmd+Enter, a restore returns the natural frame, not the right-half frame.
9. **Owner requirement**: moving a tiled or maximized window to another monitor (Space+arrow, or a repeated hotkey that cycles monitors) keeps the natural frame. The restore then happens on whichever monitor the window is on (see "Restoring on a different monitor").
10. **Candidate**: the existing undo hotkey (Ctrl+Opt+Cmd+Z, one step back through recorded frames) stays separate from restore and is unchanged.

## Edge-drag snapping

Requirement 11 is built (TKT-047) and documented in full, with its quick select panel, in `edge-drag.md`. Requirements 12 to 14, untiling by dragging away, are TKT-038 and not built.

11. **Owner requirement**: dragging a window to the edge of a screen tiles it, as BetterTouchTool and Rectangle Pro do. The natural frame from before the drag is remembered the same way the hotkeys remember it.
12. **Owner requirement**: dragging a tiled window away from the edge, by clicking and dragging it with the mouse, restores its natural **size** only. The position follows the mouse during the drag, not the natural position.
13. **Owner requirement**: this applies to windows tiled by hotkey as well as by edge drag. After natural → Left → Right → Enter, dragging the window away restores the natural size, not the right-half size.
14. **Owner requirement**: the green button restores size **and** position, while a drag restores size only.

## Restoring on a different monitor

15. **Owner requirement**: when a window is restored on a monitor other than the one its natural frame was on, the position is scaled relative to the current monitor, and the window stays fully reachable by the mouse. Example from the owner: a window was maximized on monitor 1, Ctrl+Opt+Cmd+Enter moved it to another monitor, and the green button then restores it there with its position scaled.
16. **Owner requirement**: the size stays the natural size when it fits on the current monitor.
17. **Owner requirement**: when the natural size does not fit the current monitor, the size is scaled from the original monitor to the current one.

The owner's worked example: a 400 × 400 window at x = 3000, y = 1000 on a 3440 × 1440 monitor, about 40 px from the right and bottom edges, restored on a 1000 × 1000 monitor. The owner estimated x ≈ 588 and y ≈ 572, with the size staying 400 × 400.

**Candidate** mapping, which reproduces those figures: scale the position as a fraction of the **free space** on each axis, the screen size minus the window size.

```
x' = sx' + (x - sx) / (sw - w) * (sw' - w')
y' = sy' + (y - sy) / (sh - h) * (sh' - h')
```

For the example: x' = 3000 / 3040 × 600 = 592.1, and y' = 1000 / 1040 × 600 = 576.9. That is within 5 px of the owner's estimate, and the window keeps its small gap to the right and bottom edges. Scaling the raw coordinates by the screen ratio instead (3000 / 3.44 = 872, 1000 / 1.44 = 694) would place the window's right edge at 1272 on a 1000-wide screen, which is the unreachable result requirement 15 rules out.

**Candidate** for requirement 17: on each axis where the natural size exceeds the current screen, use the window's fraction of its original screen on that axis (w' = w / sw × sw'), then clamp the frame to the screen. An axis that fits keeps its natural size.

## Which windows

18. **Owner requirement**: memory is per window, including several windows of one app, such as multiple Chrome windows. **Candidate**: keyed by the window ID (`hs.window:id()`, a CGWindowID), which is unique per window.

## Persistence

19. **Owner requirement**: memory survives a Hammerspoon reload. AutoReload reloads on every config save.
20. **Owner requirement**: memory never acts on stale values. If Hammerspoon closes and reopens 30 minutes later, it must not manage windows that moved or changed while it was not running.
21. **Owner requirement**: a frame this system placed is never mistaken for the natural frame. Example from the owner: a window at its natural frame is maximized, Hammerspoon is closed and reopened, and then Ctrl+Opt+Cmd+Right is pressed. A later restore returns the natural frame, not the maximized frame.
22. **Owner idea, deferred**: surviving a reboot, so that windows macOS restores to tiled positions can still be untiled by dragging. Window IDs change when an app relaunches, so this needs a different way of matching windows. Not in the first version.

**Owner agreed** design, following the owner's suggestion of keeping two sets of values:

- Each window keeps two records: the natural frame (`original`, with the frame of the screen it was on) and the managed frame (`applied`, with the kind of tile).
- An entry is **trusted** only while the window's current frame matches `applied` within 1 pt. A window that moved since this system last placed it is not managed from stale memory. This covers requirement 20 without a time limit.
- A frame that looks like a tile or a maximize is never recorded as the natural frame. That covers requirement 21 and the case of a window tiled before Hammerspoon started.
- A tile chain updates `applied` and leaves `original` alone (requirement 8).
- Stored in `hs.settings`, loaded at start, with entries for windows that no longer exist pruned.

## Windows with no memory

23. **Owner requirement**: if the green button is clicked on a maximized window with no trusted memory, for example one maximized before Hammerspoon started or by another app, the app's own **Window > Move & Resize > Return to Previous Size** is used. If that menu item is not available, the window is resized to about two thirds of the screen's width and height, centered.

## Displays changing

24. **Owner requirement**: docking and undocking, adding or removing a Sidecar iPad, and moving a monitor between computers through a KVM-style switch are left to macOS. This system does not fight macOS's own window handling during those transitions. macOS may put a window back where it was before an undock if the window was not touched in between.
25. **Candidate**, following from 24: the memory reacts only to the owner's own actions (a hotkey, a green-button click, later a drag). It has no display watcher, no timer, and never moves a window on its own. An entry whose window no longer matches `applied` is kept **dormant** rather than deleted, so if macOS later returns the window to exactly that frame, the entry becomes trusted again. An entry is replaced when the owner acts on a window whose dormant entry no longer matches.

## Animation

26. **Owner requirement**: moves should feel natural. An instant snap can be off-putting.
27. **Owner requirement**: an animation that feels laggy or choppy is worse than none. Hammerspoon's `setFrame(frame, duration)` animates by calling `setFrame` on the window every 0.017 s with a quadratic ease-out (`hs/window.lua`, `animate`). Each step waits for the app to re-layout, so smoothness depends on the app.
28. **Owner agreed**: measure Hammerspoon's animation on real windows before deciding. If it is choppy, the animation moves into a native piece outside Hammerspoon, like the native module considered for posting scroll events. Animation stays switchable on and off.

## Placement rules this depends on

- **Owner requirement**: sides of a window flush with the screen's usable frame have no gap, and every other side has a 1 pt gap. A maximized window has no gap on any side. A left half has its gap on the right only.
- **Owner requirement**: the green button and Ctrl+Opt+Cmd+Enter maximize to the identical frame.

## Edge cases

| # | Scenario | Expected |
|---|---|---|
| 1 | Natural → Enter → green click | Natural size and position |
| 2 | Natural → Left → Right → Enter → green click | Natural size and position, not the right half |
| 3 | Natural → Left → Right → Enter → drag away | Natural size, position under the mouse |
| 4 | Maximized on monitor 1, Enter cycles it to monitor 2, green click | Natural size, position mapped by free space onto monitor 2 |
| 5 | Same as 4, natural size larger than monitor 2 | Size scaled by screen fraction on the axes that overflow, frame clamped to monitor 2 |
| 6 | Maximized window, green click again after restoring | Maximizes again, capturing the restored frame as natural |
| 7 | Green click on a maximized window | Restore, never a resize (the 1 pt incident) |
| 8 | Two Chrome windows, each tiled differently | Each restores to its own natural frame |
| 9 | Maximized, Hammerspoon reloads, green click | Natural frame restored |
| 10 | Maximized, Hammerspoon quits, window moved by hand, Hammerspoon starts, green click | Window not trusted. Treated as no memory (row 13) if it looks maximized, otherwise maximized with its current frame as natural |
| 11 | Maximized, Hammerspoon restarts, window untouched, Ctrl+Opt+Cmd+Right, later restore | Natural frame from before the maximize, not the maximized frame |
| 12 | Window tiled before Hammerspoon ever saw it, then tiled again | Tiled frame not recorded as natural. Restore uses row 13 |
| 13 | Maximized window with no trusted memory, green click | Return to Previous Size, else about two thirds centered |
| 14 | Undock while a window is maximized by this system | Nothing happens. macOS moves the window and the entry goes dormant |
| 15 | Redock and macOS puts the window back exactly where it was | Entry trusted again. Green click restores as in row 1 |
| 16 | Window moved by hand after tiling, then a new tile | Old entry replaced. The hand-placed frame becomes the natural frame |
| 17 | Option-click on the green button | Real macOS full screen, memory untouched |
| 18 | Double-click on a title bar | Same as a green-button click: maximize, or restore when maximized. The system's Fill does not run |
| 19 | Double-click on a control in the title band (a tab button, a toolbar button, a text field) | Left to the app |
| 20 | Double-click below the top 40 pt of a window | Left to the app |

## Implementation status

The memory is part of CaddieCore (TKT-036, TKT-037):

- WindowState (`Spoons/CaddieCore.spoon/window/`, reached through `CaddieCore.window()`) holds the memory. Every placement goes through its `place` action: TileManager's hotkeys with source `tile`, EdgeSnap's drops with `snap`, and TitleBarTweaks' green button and double-click with `titlebar`. Each completed placement records the entry, and a completed `restore` forgets it. Entries are stored in `hs.settings` under `WindowState.memory`. A size-only restore is not written yet.
- TitleBarTweaks' toggle calls WindowState's `restore` when a trusted entry says the window is maximized, or when it fills its screen within 20 pt. With no natural frame, the restore falls back to Return to Previous Size, then two thirds centered. WindowState's preset and gap rules shape the green button's maximize the same as Ctrl+Opt+Cmd+Return's.
- Moves are instant (`setFrame` with duration 0). Animation is pending the measurement in requirement 28.
- Tests: `test/test_windowmemory.lua` runs edge-case rows 1, 2, 4, 5, 6, 8 to 16 against the real Spoons. `test/test_titlebartweaks.lua` covers the toggle and rows 18 to 20, and `test/test_windowstate.lua` covers WindowState on its own.
- Edge-drag tiling (TKT-047) is built in `EdgeSnap.spoon`. Its drops pass the frame from before the drag as `previousFrame`, so WindowState records it as natural. See `edge-drag.md`.
- Not built, each with a ticket holding its design notes and open questions in the `hammerspoon` project's engrata layer: drag-to-untile with its size-only restore (TKT-038), animation (TKT-040), reboot recovery (TKT-048). A glide following the cursor across windows is TKT-041, and the native posting module is TKT-039.
- macOS's own edge tiling was off on the owner's machine (`com.apple.WindowManager` `EnableTilingByEdgeDrag = 0`, `EnableTopTilingByEdgeDrag = 0`). With it on, macOS would tile on the same drag edge snapping uses, and WindowState would not see that placement.
- Tickets: TKT-001 (green button), TKT-002 (tiling), TKT-036, TKT-037 in the `hammerspoon` project.

## Status markers

Every design statement carries one of these:

- **Owner requirement**: stated by the owner.
- **Owner agreed**: proposed in discussion and explicitly accepted by the owner.
- **Candidate**: proposed and not yet reviewed. Open to change at pickup.
- **Measured**: backed by a recorded measurement run.
