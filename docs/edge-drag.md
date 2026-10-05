# Edge-drag tiling and the quick select panel

Last Updated: 2026-10-04

Status markers are defined in `window-memory.md`. This document records how dragging a window to a screen edge tiles it, and how the quick select panel offers the placements near the cursor while the drag is held. The owner shaped the behavior over one working session, trying each step live and directing the next. The code is `Spoons/EdgeSnap.spoon/`, with the quick select panel in its `panel/` directory, tracked as TKT-047 in the `hammerspoon` project. Values quoted here are the defaults.

## 1. Origin

TKT-047 began as "drag a window to a screen edge to tile it, as BetterTouchTool and Rectangle Pro do" (requirement 11 in `window-memory.md`). The owner first decided to rely on macOS's own edge tiling and add only the bottom edge, which macOS lacks. After seeing the bottom edge working, the owner asked for the left, right, and top edges and the corners as well, in the manner macOS presents them. macOS edge tiling is off on the owner's machine (`com.apple.WindowManager` `EnableTilingByEdgeDrag = 0`, `EnableTopTilingByEdgeDrag = 0`), so EdgeSnap is the only edge tiling running there.

The quick select panel came from BetterTouchTool, which the owner had been seeing without realizing it was still running after a reboot. BetterTouchTool shows a small box of choices beside the edge, so a corner can be chosen without travelling all the way to it. The owner asked for the same, then reshaped it through a series of adjustments, each tried live.

## 2. Terms

- **Usable frame**: a screen's frame below the menu bar and above a visible Dock, as `hs.screen:frame()` reports it. Edges and corners are measured from it.
- **Edge zone**: the band inside an edge that counts as being at that edge, `edgeZone` points deep, reaching outward to the physical edge.
- **Corner zone**: the stretch of an edge within `cornerZone` points of a corner.
- **Placement**: where a drop puts the window: a half, a quarter, the bottom half, or maximize.
- **Preview**: the translucent rectangle showing where a drop would put the window.
- **Panel**: the quick select panel. A **line** is three cells along one edge. An **L** joins the two lines meeting at a corner.
- **Strip**: the band a panel selects across, from the physical screen edge to the panel's far side.
- **Span**: the stretch along the edge where a panel's cells select.
- **Seam**: an edge two screens share.

## 3. Detecting a window drag

**Owner agreed.** EdgeSnap never asks the window server or Accessibility from inside an event-tap callback. Each tap records the event and schedules a one-shot timer, held on the Spoon so it isn't collected before firing.

1. CaddieCore's shared title-bar click tap (`CaddieCore.titlebar()`) passes EdgeSnap every left mouse-down and mouse-up that TitleBarTweaks has not swallowed.
2. On mouse-down, a timer looks up the topmost normal window under the point through `hs.window.list()`, front to back. If the point lies in that window's top 40 pt (`TITLE_BAR_H`), EdgeSnap records the window's id, its process, its bounds before the drag, and each screen's frames, then holds CaddieCore's shared `leftMouseDragged` tap. The tap exists only while someone holds it, until mouse-up here, so drags that don't start in a title band cost nothing more.
3. The first time the cursor reaches an edge, EdgeSnap reads the window's bounds once more. A window that moved less than 3 pt (`MOVED_MIN`) isn't being dragged. That excludes text selection, a click on the green button, and a tab torn out of a Chrome window, where the original window stays put.

## 4. Edges and placements

**Owner requirement.**

| Edge | Placement |
|---|---|
| Left | Left half |
| Right | Right half |
| Top | Maximize, matching macOS |
| Bottom | Bottom half |
| Within a corner zone | That corner's quarter |

- **Measured from the usable frame, Owner requirement.** The top edge starts at the bottom of the menu bar and the zone reaches 16 pt below it, so pushing into the menu bar counts without travelling to the physical top. The menu bar's height is read per screen at drag start: 39 pt under the built-in display's notch and 30 pt on the external display, as read.
- **Window pinned against the menu bar, Owner requirement.** macOS stops a dragged window at the menu bar while the cursor stays as far below its top as it was grabbed. At mouse-down EdgeSnap records that grab offset. A cursor within the offset plus 3 pt (`PIN_SLACK`) of the usable top counts as the top edge, so the cursor need not be pushed up through the title bar. This applies only to a top edge with no screen above it.
- **Shared edges, Owner requirement.** Each side of a seam counts as an edge of the screen the cursor is on (`seams = true`). The owner tried a 0.2 s, 0.1 s, and 0.05 s wait before a seam counted (`seamDelay`), then a seam-only slowdown of the animations (`seamTween`), and finally set both to 0 with the slower animation applied to every edge instead (§ 6).

## 5. Corner zones

**Owner requirement.** Every corner of every screen reaches 144 pt (`cornerZone`) along both of its edges, measured from the usable frame, whatever the screen's size and whether or not either edge is shared. The owner described a screen as a box whose corners all reach the same distance.

The zone was first a fraction of each edge: 15%, then 7.5%. A fraction gave different distances on different edges. At 7.5% the built-in display's corners reached about 97 pt along its 1290 pt sides and about 154 pt along its 2056 pt top and bottom, and the owner noticed the difference. A fixed distance replaced it, first 96.75 pt (the 7.5% of the built-in side), then 144 pt, which the owner chose as 48 pt × 3.

A reach longer than half an edge is capped at half, so the two corners of a short edge can't overlap.

## 6. The preview

**Owner agreed.** While a dragged window is held at an edge, a rounded translucent rectangle shows the placement, inset 6 pt with a 10 pt corner radius. It grows out of the point where the cursor reached the edge and fades in. Moving between placements glides it from one to the next.

| | Value | Source |
|---|---|---|
| Grow | 0.31 s, cubic bezier (0.1, 0.9, 0.2, 1) | Rectangle's 0.26 s and curve (`WindowAnimationCurves.swift`), plus 0.05 s |
| Fade in | 0.23 s, cubic `t(3 + t(t - 3))` | Rectangle's 0.18 s and curve, plus 0.05 s |
| Fade out | 0.12 s | Rectangle's |

Apple publishes no timing for its own tiling. Rectangle's source was the nearest documented reference. Rectangle ships its grow animation off (`footprintAnimationDurationMultiplier` defaults to 0), so the growing preview here is the owner's choice rather than Rectangle's default. The extra 0.05 s was first applied to shared edges only, and the owner then asked for it on every edge.

## 7. The panel

### 7.1 Lines

**Owner requirement.** At an edge outside its corner zones, a line of three cells appears just inside the edge, centered on the cursor along it and kept on screen:

| Edge | Cells, in order along the edge |
|---|---|
| Left | Top left, Left side, Bottom left |
| Right | Top right, Right side, Bottom right |
| Top | Top left, Maximize, Top right |
| Bottom | Bottom left, Bottom half, Bottom right |

The left and right lines are columns 78 × 186 pt and the top and bottom lines are rows 216 × 68 pt, 4 pt in from the edge. Each cell is 64 × 54 pt, a size the owner set by asking for 64 pt cells at the first layout's aspect ratio, with 7 pt padding and 5 pt between cells. Each cell carries a small screen icon with its region filled. The selected cell is lit blue and labeled beside a column, or under or over a row. The panel is 92% opaque with a 1 pt outline at 35% white and a 15 pt radius. It fades with the preview's timings.

### 7.2 Selecting

**Owner requirement.** Across the edge the panel is forgiving and along it the panel is precise.

- **Across**: anywhere in the strip counts, from the physical screen edge to the panel's far side, 82 pt in for a column. The cursor reaches the edge faster than the panel appears and stops against the screen edge, beside the panel rather than in it. An early version required the cursor inside the panel, and the owner found themselves reversing to reach it.
- **Along**: a cell counts only within the panel's own length. Inside it, the middle cell's band, gaps included, selects the edge's own placement, and the stretch either side selects the corner cells. Past either end of the panel the edge's own placement is selected: the left half at the left edge, for example. An earlier version let the end cells reach the ends of the screen, so a panel that opened high kept Bottom left selected however far down the cursor went.
- **Leaving the strip** closes the panel. A release there does nothing.

### 7.3 The magnet

**Owner requirement.** The panel opens where the cursor reaches the edge and stays there while the cursor moves within it.

- Up to 16 pt past either end (the edge-zone depth) the panel doesn't move.
- Beyond that it is pulled after the cursor so that its nearest end trails the cursor by 16 pt. The cells move at once, and the drawing eases after them like a smooth scroll: each frame it covers the share of the remaining distance that a 0.08 s time constant gives (`pickerFollow`).
- Moving back toward the panel leaves it where it was pulled to. The first cell met coming back is the near end's corner cell.
- Passing 16 pt beyond the opposite end starts the pull in that direction.

The owner tried, in order, a panel that reopened centered on the cursor, a jump from one spot to the next with a short glide, and a panel always centered on the cursor, before describing the magnet. The last two made the corner cells hard or impossible to reach. The magnet keeps the panel within reach without choosing a cell on the owner's behalf.

### 7.4 The L

**Owner requirement.** In a corner zone the panel is an L: the side's column and the edge's row, both tucked into the corner, sharing the corner cell. In the bottom-left corner the column runs Top left, Left side, Bottom left up the left edge, and the row runs Bottom left, Bottom half, Bottom right along the bottom. Bottom left appears once. The shared cell's label sits in the L's inner corner and the other labels beside their arm.

- Each arm selects along its own length, and its span runs on to the screen corner, where nothing lies beyond. Where the two strips cross, at the corner, the shared cell is selected.
- Flinging a window straight into a corner opens the L with the corner cell selected, so an immediate release gives the quarter.
- The L is drawn as a single closed path with all six corners rounded, the inner one included. Two overlapping rounded rectangles were tried first and doubled the outline where their edges ran together.

### 7.5 From a line into the L

**Owner requirement.** A line following the cursor toward a corner doesn't jump to the L as the cursor enters the corner zone. It keeps following until its end is within `cornerSnap` points of the corner. It is then drawn into the corner, harder than the follow (`cornerPull`, a 0.04 s time constant, half the follow's), and the L is drawn the moment it arrives. The column or row is already in its place, so the line appears to grow its second arm.

`cornerSnap` was tried at 32, 48, 96, 192, and 288 pt. Inside a 144 pt corner zone a following line's end is never more than about 160 pt from the corner, so at 192 pt and above the corner zone decides and the line becomes the L as soon as the cursor enters it. 288 pt is the default.

Selection belongs to the L from the moment it takes over, so a release during the pull gives the L's cell. While the line is gliding in, its matching cell is lit.

An earlier version showed the L early, unlit, beside the following line. The owner found the two panels redundant.

### 7.6 Out of the L

**Owner requirement.** Leaving an L past the far end of one arm keeps that arm in place as a line and drops the other. The magnet carries on from there. Leaving the bottom-left L along the bottom turns its row into the bottom line, where it was, and the line then follows the cursor right. An earlier version opened a fresh line centered on the cursor, which jumped about half its length.

## 8. The drop

On mouse-up EdgeSnap works out the selection for the release point once more. If the window was confirmed moving and a placement is selected, a timer after the mouse-up runs WindowState's `place` action (`CaddieCore.window()`) with source `snap`, so nothing resizes the window while macOS is still dragging it. The placement carries:

- the screen under the cursor, whose usable frame the tile is cut from. A window hanging off an edge can sit mostly on another screen, and a drop never cycles on to the next screen as a repeated hotkey does.
- `previousFrame`: the window's frame from before the drag. WindowState records it as the natural frame, so the green button later restores it, and Ctrl+Opt+Cmd+Z returns there.

Gaps, presets, and the rest of WindowState's rules apply as they do for the hotkeys. A guard registered on `place` by anyone else can veto a drop by checking for source `snap`.

## 9. The Mission Control guard

**Owner requirement.** Dragging a window into the top of the screen and pushing on can open Mission Control, and the owner reported it opening before intended. EdgeSnap carries the guard Rectangle offers. With the cursor held at the top pixel of a screen on two consecutive drag events, an upward jump of more than 25 pt in one event (`guardDistance`) is rewritten 1 pt lower, and so is any event held at the top for 0.25 s after (`guardSeconds`). Like Rectangle, the next event is judged from the rewritten position, so the guard doesn't hold every event in that window. A slow push still reaches Mission Control.

Rectangle installs this filter only when its user turns off `missionControlDragging`. EdgeSnap has it on (`missionControlGuard = true`) and skips a top edge with a screen above it, where it would stop a drag onto that screen. macOS has its own option for this drag behavior under Desktop & Dock. Turning it off would make the guard unnecessary. Its state on the owner's machine wasn't confirmed: the defaults key checked was absent, and that key's name was a guess.

## 10. Drawing and animation

**Owner agreed.**

- Two canvases at the overlay level, the preview and the panel, created in `:start()` and deleted in `:stop()`.
- One 60 Hz timer drives every animation and exists only while something is moving. Each canvas has at most one animation, and a new one starts from wherever the last one left it.
- Fades use EdgeSnap's own animator. `hs.canvas`'s built-in `show(fade)` and `hide(fade)` left the panel at alpha 0, read back from the live canvas, and the owner had seen it partly transparent before that. A hide interrupted by a quick return to the edge is the suspected cause, not confirmed.
- A follow glide carries its own position rather than reading the canvas frame back. On the 1× external display the canvas rounds its frame to whole points, and a step under one point rounded back to the same spot, so a glide toward the L never arrived and the L never appeared there. That diagnosis is inferred. The test that fakes whole-point rounding fails without the fix and passes with it.
- Each panel's canvas reaches 2 pt past the panel, since its outline is stroked centered on the edge and half of it lies outside. Without the margin the outline was clipped.
- Panel drawing is rebuilt only when the selection or the panel changes, never per mouse move.

## 11. Settings

All on the EdgeSnap Spoon.

| Setting | Default | Meaning |
|---|---|---|
| `edgeZone` | 16 | Points inside the usable frame that count as an edge. Also the magnet's lag |
| `cornerZone` | 144 | Points from each corner, along both edges, that count as that corner |
| `edgePicker` | true | Show the panel |
| `seams` | true | A shared edge counts as an edge |
| `seamDelay` | 0 | Seconds the cursor must stay at a shared edge before it counts |
| `seamTween` | 0 | Seconds added to animations at a shared edge |
| `pickerFollow` | 0.08 | Time constant of the panel's follow, in seconds |
| `cornerSnap` | 288 | Points from the corner at which a following line becomes the L |
| `cornerPull` | 0.04 | Time constant of the pull into the corner, in seconds |
| `missionControlGuard` | true | Rectangle's Mission Control guard |
| `guardDistance` | 25 | Upward jump, in points, that the guard catches |
| `guardSeconds` | 0.25 | How long the guard holds after a jump |
| `previewGrow` | 0.31 | Preview grow, in seconds |
| `previewFadeIn` | 0.23 | Preview and panel fade in, in seconds |
| `previewFadeOut` | 0.12 | Preview and panel fade out, in seconds |

Panel geometry is fixed in `panel/shape.lua`: cells 64 × 54, padding 7, gap 5, 4 pt from the edge, labels 128 × 27 at 10 pt, icons 42 × 27, 2 pt canvas margin.

## 12. Code

All under `Spoons/EdgeSnap.spoon/`:

- `init.lua`: the settings, `:start()`, and `:stop()`.
- `drag.lua`: the taps, through `CaddieCore.titlebar()` (`_onClick`, `_down`, `_onDrag`, `_endDrag`).
- `zones.lua`: edges, corners, and seams (`_zoneAt`, `_seam`).
- `resolve.lua`: selection, the magnet, and the line becoming the L (`_resolve`, `_approaching`, the seam dwell).
- `display.lua`: confirming the drag and drawing the panel (`_zone`, `_drawPicker`, `_drawMorph`, `_follow`).
- `animate.lua`: the animator (`_animate`, `_animTick`, `_followStep`).
- `preview.lua`: the preview canvas (`_showPreview`, `_hidePreview`).
- `guard.lua`: the Mission Control guard (`_guardTop`).
- `drop.lua`: the drop through WindowState (`_drop`).
- `constants.lua`: distances and mappings the parts share.
- `panel/`: the quick select panel. `shape.lua` holds its sizes and cells, `layout.lua` places lines and the L, `select.lua` hit-tests (`hit`, `inStrip`, `armAt`), `magnet.lua` moves lines (`magnet`, `alignTo`, `toCorner`), `render.lua` draws, and `init.lua` gathers them into one table, also published as `EdgeSnap.panel`.

CaddieTools' `use()` starts EdgeSnap after TitleBarTweaks whatever order they are listed in, so a click TitleBarTweaks swallows never arms a drag. A config that starts them itself has to keep that order.

## 13. Tests

`test/test_edgesnap.lua` runs EdgeSnap with the real CaddieCore, WindowState, TileManager, and TitleBarTweaks on the owner's two-screen layout, with fake windows, a fake canvas, and synthetic tap events. The fake canvas copies frames as `hs.canvas` does and can round them to whole points as on a 1× screen. Stub timers never tick, so animated states are checked by stepping `_animTick` by hand.

The tests cover every edge and corner of both screens, the pinned top, seams, both corner reaches at their boundaries, each panel shape and cell, the magnet in both directions, the line becoming the L and an arm leaving it, the guard, the drop with WindowState's memory and undo, the canvas margins, the outline path, and cleanup on `:stop()`.

## 14. Open

- **A drag that didn't arm.** A temporary logger recorded a mouse-down at 3165,853 on the external display that didn't start a drag. The owner stopped the investigation there. The cause is unknown.
- **Perceived distance at the built-in display's right edge.** The owner reported that a line heading down the left edge becomes the L from about three times farther from the corner than a line heading along the bottom toward the shared right edge, after the fixed corner reach made the two the same in code. The logger captured no drags before the owner stopped it. Unresolved.
- **Fill to next window.** BetterTouchTool offers a fourth cell that sizes the window from the edge to the nearest other window. Filed as TKT-050.
- **The line's corner cells while it follows** can only be reached by moving back toward the panel or into a corner zone. The owner accepted that while the magnet was settled.
- **The other placements.** Thirds, two thirds, and the top half have no edge or panel position.
- **Hot corners.** The owner's bottom-right hot corner opens Quick Note (`wvous-br-corner = 14`). A drag pushed into that pixel may trigger it.
