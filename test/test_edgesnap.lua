-- Run: lua test/test_edgesnap.lua   (from the repo root)
-- EdgeSnap with the real Core, WindowState, TileManager, and TitleBarTweaks: a window
-- dropped on a screen edge tiles there through WindowState.
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end
local function same(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end
local function show(f)
  return f and string.format("%s,%s %sx%s", f.x, f.y, f.w, f.h) or "nil"
end

-- The owner's two monitors, side by side, each with a menu bar and an auto-hiding Dock
local LEFT_FULL = { x = 0, y = 0, w = 2056, h = 1329 }
local LEFT = { x = 0, y = 39, w = 2056, h = 1290 }
local RIGHT_FULL = { x = 2056, y = 0, w = 2048, h = 1280 }
local RIGHT = { x = 2056, y = 30, w = 2048, h = 1250 }

local screens = {}
local function fakeScreen(id, full, frame)
  return {
    id = function() return id end,
    frame = function() return frame end,
    fullFrame = function() return full end,
  }
end
local function screenOf(f)
  local cx, cy = f.x + f.w / 2, f.y + f.h / 2
  for _, s in ipairs(screens) do
    local r = s:fullFrame()
    if cx >= r.x and cx < r.x + r.w and cy >= r.y and cy < r.y + r.h then return s end
  end
  return screens[1]
end

-- Front to back, as hs.window.list() reports them
local order = {}
local focused = nil
local function fakeWindow(id, frame)
  local w = { _id = id, f = frame }
  table.insert(order, 1, w)
  function w:id() return self._id end
  function w:frame() return { x = self.f.x, y = self.f.y, w = self.f.w, h = self.f.h } end
  function w:setFrame(r) self.f = { x = r.x, y = r.y, w = r.w, h = r.h } end
  function w:screen() return screenOf(self.f) end
  function w:focus() focused = self end
  function w:application()
    return {
      bundleID = function() return "com.example.app" end,
      findMenuItem = function() return nil end,
      selectMenuItem = function() return false end,
    }
  end
  return w
end

local preview = {}
local function fakeCanvas()
  local c = { shown = false }
  function c:level() end
  function c:behavior() end
  function c:appendElements() end
  -- Copied, as hs.canvas does, so a panel moved in place does not move its canvas.
  -- Rounded to whole points when ROUND_FRAMES is set, as on a 1x screen.
  function c:frame(f)
    if f then
      local r = ROUND_FRAMES and math.floor or function(v) return v end
      self.f = { x = r(f.x + (ROUND_FRAMES and 0.5 or 0)), y = r(f.y + (ROUND_FRAMES and 0.5 or 0)), w = f.w, h = f.h }
    end
    return self.f or { x = 0, y = 0, w = 1, h = 1 }
  end
  function c:alpha(a)
    if a then self.a = a end
    return self.a or 1
  end
  function c:replaceElements(els) self.els = els end
  function c:show() self.shown = true end
  function c:hide() self.shown = false end
  function c:delete() self.deleted = true end
  -- EdgeSnap makes the preview first and the corner panel second
  if not preview.canvas then preview.canvas = c else preview.picker = c end
  return c
end

local function boot()
  preview.canvas, preview.picker = nil, nil
  for name in pairs(package.loaded) do
    if name:match("^%u%a+$") then
      package.loaded[name] = nil
    end
  end
  stub.install(".")
  hs.screen.allScreens = function() return screens end
  hs.screen.watcher.new = function() return { start = function(s) return s end, stop = function() end } end
  hs.settings = { get = function() return nil end, set = function() end }
  hs.timer.usleep = function() end
  -- The stub runs a one-shot at once and returns a handle, which would land after
  -- the callback cleared it. Real timers fire after the caller stores the handle.
  hs.timer.doAfter = function(_, fn) fn() return nil end
  hs.canvas = { new = fakeCanvas, windowLevels = { overlay = 0 } }
  hs.window.focusedWindow = function() return focused end
  hs.window.list = function()
    local out = {}
    for _, w in ipairs(order) do
      out[#out + 1] = { kCGWindowNumber = w._id, kCGWindowLayer = 0, kCGWindowOwnerPID = 1,
        kCGWindowBounds = { X = w.f.x, Y = w.f.y, Width = w.f.w, Height = w.f.h } }
    end
    return out
  end
  stub.loadSpoon("CaddieCore"):start().window().gap = 1
  local tiler = stub.loadSpoon("TileManager")
  local gb = stub.loadSpoon("TitleBarTweaks")
  local drag = stub.loadSpoon("EdgeSnap")
  -- The stub's repeating timers never fire, so the preview animates in one step
  drag.previewGrow, drag.previewFadeIn, drag.previewFadeOut = 0, 0, 0
  -- Shared edges count at once and animate like any other here. The dwell and the
  -- slower shared-edge animation have their own tests.
  drag.seamDelay, drag.seamTween, drag.pickerFollow, drag.cornerPull = 0, 0, 0, 0
  drag:start()
  return tiler, gb, drag
end

screens = { fakeScreen(1, LEFT_FULL, LEFT), fakeScreen(2, RIGHT_FULL, RIGHT) }
local tiler, gb, drag = boot()

-- `dy` is the event's upward or downward movement, read by the Mission Control guard
local function event(kind, x, y, dy)
  local e = { loc = { x = x, y = y } }
  function e:getType() return kind end
  function e:location(pt)
    if pt then self.loc = pt end
    return { x = self.loc.x, y = self.loc.y }
  end
  function e:getProperty() return dy or 0 end
  return e
end

-- Presses in the window's title bar, drags through each point carrying the window
-- with the mouse unless `stuck`, and releases at the last. Returns whether the
-- preview and the corner panel showed just before the release, and the panel's alpha.
local function dragPath(w, points, stuck, grabY)
  focused = w
  local last = { x = w.f.x + 200, y = w.f.y + (grabY or 10) }
  drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, last.x, last.y))
  for _, p in ipairs(points) do
    if not stuck then
      w.f = { x = w.f.x + p[1] - last.x, y = w.f.y + p[2] - last.y, w = w.f.w, h = w.f.h }
    end
    last = { x = p[1], y = p[2] }
    drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, last.x, last.y))
  end
  local shown, panel, alpha = preview.canvas.shown, preview.picker.shown, preview.picker:alpha()
  drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, last.x, last.y))
  return shown, panel, alpha
end

local function dragTo(w, x, y, stuck)
  return dragPath(w, { { x, y } }, stuck)
end

local function labelOf(canvas)
  for _, el in ipairs(canvas.els or {}) do
    if el.type == "text" then return el.text end
  end
  return nil
end

-- The hotkey's bottom half on each screen, for comparison
local ref = fakeWindow(100, { x = 300, y = 300, w = 600, h = 400 })
tiler:tile("down", ref)
local leftHalf = ref:frame()
ref.f = { x = 2400, y = 300, w = 600, h = 400 }
tiler:tile("down", ref)
local rightHalf = ref:frame()
order = {}

-- A drop on the middle of the bottom edge
local natural = { x = 400, y = 200, w = 800, h = 600 }
local a = fakeWindow(1, natural)
local shown = dragTo(a, 1000, 1327)
check(shown, "the preview shows while the window is held at the bottom edge")
local half = require("CaddieCore").geometry().baseTile("down", LEFT)
check(same(preview.canvas.f, { x = half.x + 6, y = half.y + 6, w = half.w - 12, h = half.h - 12 }),
  "the preview covers the bottom half, inset, got " .. show(preview.canvas.f))
check(not preview.canvas.shown, "the preview hides on release")
check(same(a.f, leftHalf), "a drop on the bottom edge tiles to the hotkey's bottom half, got " .. show(a.f))

-- The green button maximizes a half, then restores the frame from before the drag
gb:toggle(a)
local r = gb:toggle(a)
check(r.mode == "restore" and same(a.f, natural), "the green button later restores the frame from before the drag, got " .. show(a.f))

-- Undo returns the window to where it was before the drag
dragTo(a, 1000, 1328)
check(same(a.f, leftHalf), "dropped again")
local undone = require("CaddieCore").window().undoStack:pop(1)
check(same(undone, natural), "undo returns the frame from before the drag, got " .. show(undone))

-- The tile lands on the screen under the cursor, even with the window mostly elsewhere
a.f = { x = 1200, y = 200, w = 800, h = 600 }
dragTo(a, 2100 + 400, 1279)
check(same(a.f, rightHalf), "a drop on the right screen's edge tiles there, got " .. show(a.f))

-- The hotkey's frame for a placement, on the screen holding (x, y)
local function hotkeyFrame(position, x, y)
  local r = fakeWindow(101, { x = x - 100, y = y - 100, w = 200, h = 150 })
  if position == "maximize" then tiler:maximize(r) else tiler:tile(position, r) end
  table.remove(order, 1)
  return r:frame()
end

-- Every edge and corner of the left screen. Its right edge meets the right screen,
-- so that side is a seam except at the corners on the top and bottom edges.
local b = fakeWindow(2, { x = 400, y = 200, w = 800, h = 600 })
local before = b:frame()
local drops = {
  { 1, 600, "left", "the left edge tiles the left half" },
  { 1000, 1, "maximize", "the top edge maximizes from inside the menu bar" },
  { 1000, 39 + 15, "maximize", "and from just under the menu bar, which is the top edge" },
  { 3000, 30 + 15, "maximize", "under the shorter menu bar of the external screen too" },
  { 15, 600, "left", "the zone reaches 15 pt in from the left edge" },
  { 2, 100, "topLeft", "the left edge near the top tiles the top-left quarter" },
  { 50, 1328, "bottomLeft", "the bottom edge near the left tiles the bottom-left quarter" },
  { 2000, 1328, "bottomRight", "the bottom edge near the seam still tiles the bottom-right quarter" },
  { 2000, 2, "topRight", "the top edge near the seam tiles the top-right quarter" },
  { 4102, 600, "right", "the right screen's right edge tiles its right half" },
  { 4100, 1278, "bottomRight", "the right screen's bottom-right corner tiles that quarter" },
}
for _, d in ipairs(drops) do
  b.f = before
  dragTo(b, d[1], d[2])
  local want = hotkeyFrame(d[3], d[1], d[2])
  check(same(b.f, want), d[4] .. ", got " .. show(b.f) .. " want " .. show(want))
end

b.f = before
dragTo(b, 2054, 600)
check(same(b.f, hotkeyFrame("right", 300, 300)), "the left screen's side of the seam tiles its right half, got " .. show(b.f))
b.f = before
dragTo(b, 2060, 600)
check(same(b.f, hotkeyFrame("left", 3000, 300)), "the right screen's side tiles its left half, got " .. show(b.f))
b.f = before
_, panel = dragPath(b, { { 2054, 600 }, { 2060, 600 } })
check(panel and labelOf(preview.picker) == "Left side", "crossing the seam moves the panel to the other screen's edge")
-- With a dwell, a shared edge counts only once its timer fires. The timer is held
-- here rather than run, so the test decides when the cursor has stayed long enough.
local pending = nil
local runNow = hs.timer.doAfter
hs.timer.doAfter = function(secs, fn)
  if secs > 0 then
    pending = fn
    return { stop = function() pending = nil end }
  end
  return runNow(secs, fn)
end
drag.seamDelay = 0.2
b.f = before
focused = b
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
b.f = { x = before.x + 1454, y = before.y + 390, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 2054, 600))
check(not preview.canvas.shown and pending ~= nil, "at a shared edge with a dwell, nothing shows until the timer fires")
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 2200, 600))
check(pending == nil, "moving on past the edge cancels the timer, so a drag across never flashes")
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 2054, 600))
pending()
check(preview.canvas.shown and labelOf(preview.picker) == "Right side", "staying until it fires shows the preview and panel")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 2054, 600))
check(same(b.f, hotkeyFrame("right", 300, 300)), "and releasing tiles as before")
b.f = before
_, panel = dragTo(b, 1000, 1328)
check(panel and same(b.f, hotkeyFrame("down", 300, 300)), "a real edge ignores the dwell")
hs.timer.doAfter = runNow
drag.seamDelay = 0

-- At a shared edge the cue starts at once and animates seamTween slower. The
-- stub's animation timer never ticks, so the lengthened animations are still
-- running when read.
drag.seamTween = 0.05
b.f = before
focused = b
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
b.f = { x = before.x + 1454, y = before.y + 390, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 2054, 600))
local grow = drag.anims[preview.canvas] and drag.anims[preview.canvas].grow
local fade = drag.anims[preview.picker] and drag.anims[preview.picker].fade
check(preview.canvas.shown and grow == 0.05 and fade == 0.05,
  "a shared edge shows at once, growing and fading in 0.05 s slower, got " .. tostring(grow) .. " and " .. tostring(fade))
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 2054, 600))
b.f = before
focused = b
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
b.f = { x = before.x - 599, y = before.y + 390, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 600))
check(drag.anims[preview.canvas] == nil and drag.anims[preview.picker] == nil, "a real edge animates at the usual speed")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 1, 600))
drag:_stopAnim()
drag.seamTween = 0

drag.seams = false
b.f = before
_, panel = dragTo(b, 2054, 600)
check(not panel and b.f.w == 800 and b.f.h == 600, "with seams off the shared edge does not tile")
drag.seams = true
b.f = before
dragTo(b, 1000, 1300)
check(b.f.w == 800 and b.f.h == 600, "a drop away from every edge does nothing")
b.f = before
dragTo(b, 1000, 39 + 17)
check(b.f.w == 800 and b.f.h == 600, "17 pt under the menu bar is past the top zone")

-- A top-edge drop on the other screen maximizes there rather than cycling on
b.f = before
dragTo(b, 3000, 1)
check(same(b.f, RIGHT), "a top-edge drop maximizes on the screen under the cursor, got " .. show(b.f))
dragTo(b, 3000, 1)
check(same(b.f, RIGHT), "and dropping it there again keeps it there")

-- The window did not move with the mouse, as in text selection or a torn-off tab
b.f = before
shown = dragTo(b, 1000, 1328, true)
check(not shown and same(b.f, before), "a drag that does not carry the window shows nothing and tiles nothing")

-- A press below the title band never arms the drag
b.f = before
focused = b
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 400))
check(drag.releaseDrag == nil and require("CaddieCore").titlebar().dragTap == nil, "a press in the window body arms no drag tap")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 600, 400))

-- The corner panel. On the left screen at y = 600 it spans y 507 to 693 and x 4 to
-- 82, with cells at 514, 573, and 632, each 54 high. The column from the screen
-- edge to x 82 selects by height: the side from 570.5 to 629.5, corners beyond.
local p = fakeWindow(4, { x = 400, y = 200, w = 800, h = 600 })
local home = p:frame()
focused = p
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
p.f = { x = home.x - 599, y = home.y + 390, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 600))
check(preview.picker.shown and labelOf(preview.picker) == "Left side",
  "at the left edge the panel shows with the side cell highlighted, label " .. tostring(labelOf(preview.picker)))
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 40, 550))
check(labelOf(preview.picker) == "Top left", "hovering the top cell highlights it")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 40, 550))
check(same(p.f, hotkeyFrame("topLeft", 300, 300)), "releasing on the top cell tiles the top-left quarter, got " .. show(p.f))
check(not preview.picker.shown, "the panel hides on release")

p.f = home
dragPath(p, { { 1, 600 }, { 40, 650 } })
check(same(p.f, hotkeyFrame("bottomLeft", 300, 300)), "the bottom cell tiles the bottom-left quarter")
p.f = home
dragPath(p, { { 1, 600 }, { 40, 600 } })
check(same(p.f, hotkeyFrame("left", 300, 300)), "the middle cell tiles the left half")
p.f = home
dragPath(p, { { 1, 600 }, { 1, 560 } })
check(same(p.f, hotkeyFrame("topLeft", 300, 300)), "pressed against the edge, moving up selects the top corner")
p.f = home
dragPath(p, { { 1, 600 }, { 1, 640 } })
check(same(p.f, hotkeyFrame("bottomLeft", 300, 300)), "and moving down the bottom corner")
p.f = home
dragPath(p, { { 1, 600 }, { 1, 615 } })
check(same(p.f, hotkeyFrame("left", 300, 300)), "a small drift stays on the side")

p.f = home
local _, panel = dragPath(p, { { 1, 600 }, { 40, 550 }, { 300, 550 } })
check(not panel and p.f.w == 800, "leaving the panel for open screen hides it and drops nothing")
p.f = home
_, panel = dragPath(p, { { 1, 600 }, { 1, 100 } })
check(panel and same(p.f, hotkeyFrame("topLeft", 300, 300)),
  "sliding up into the corner zone, the panel pulled to 73 pt from the top becomes the L")

-- cornerSnap: a following panel turns into the L only once its end is within that
-- many points of the corner. Pinned to 96 here so the corner zone, which starts at
-- y 1185 on the left screen, does not decide first. The L's column ends at y 1325.
drag.cornerSnap = 96
p.f = home
focused = p
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
p.f = { x = home.x - 599, y = home.y + 390, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 600))
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1240))
local near = drag.target.picker
check(not near.corner and near.rect.y + near.rect.h == 1224 and labelOf(preview.picker) == "Left side",
  "in the corner zone but 101 pt short, the panel keeps following, end at " .. (near.rect.y + near.rect.h))
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1246))
check(drag.target.picker.corner == "bottomLeft" and drag.target.morph and drag.target.morph.from == near,
  "95 pt short it is drawn into the corner and becomes the L")
check(near.rect.y + near.rect.h == 1325, "its end moved the rest of the way to the corner")
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1310))
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 1, 1310))
check(same(p.f, hotkeyFrame("bottomLeft", 300, 300)), "releasing on its corner cell tiles the bottom-left quarter")

drag.cornerSnap = 200

p.f = home
focused = p
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
p.f = { x = home.x - 599, y = home.y + 390, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 600))
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1236))
check(drag.target.picker.corner == "bottomLeft", "a larger cornerSnap turns it into the L sooner, at 105 pt")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 1, 1236))
drag.cornerSnap = 288

-- At the default 288 pt any following panel becomes the L as soon as the cursor
-- enters the corner zone, since its end is never farther than that from the corner
p.f = home
focused = p
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
p.f = { x = home.x - 599, y = home.y + 390, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 600))
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1184))
check(not drag.target.picker.corner, "just above the corner zone, 144 pt from the bottom, the panel still follows")
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1185))
check(drag.target.picker.corner == "bottomLeft", "entering it, the panel becomes the L")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 1, 1185))
p.f = home
_, panel = dragPath(p, { { 1, 600 }, { 90, 600 } })
check(not panel and p.f.w == 800, "past the panel's far side the panel closes and nothing drops")

-- On the right screen the panel sits inside its right edge, x 4030 to 4094
p.f = home
dragPath(p, { { 4102, 600 }, { 4062, 550 } })
check(same(p.f, hotkeyFrame("topRight", 3000, 300)), "the right screen's panel offers its top-right quarter, got " .. show(p.f))
check(labelOf(preview.picker) == "Top right", "with its own labels")

-- Turned off, the side edges behave as before and the panel's cells are open screen
drag.edgePicker = false
p.f = home
_, panel = dragPath(p, { { 1, 600 }, { 40, 550 } })
check(not panel and p.f.w == 800, "with edgePicker off no panel shows and its place drops nothing")
drag.edgePicker = true

-- The top and bottom panels are rows. On the left screen at x = 1000 they span x
-- 892 to 1108 with cells at 899, 968, and 1037, and the middle band runs from 965.5
-- to 1034.5. The top row sits 4 pt under the 39 pt menu bar, y 43 to 111, and the
-- bottom row 4 pt above the screen edge, y 1257 to 1325.
p.f = home
_, panel = dragPath(p, { { 1000, 1 } })
check(panel and labelOf(preview.picker) == "Maximize", "the top edge shows a row with maximize in the middle")
check(same(p.f, LEFT), "and releasing there maximizes")
p.f = home
dragPath(p, { { 1000, 1 }, { 940, 1 } })
check(same(p.f, hotkeyFrame("topLeft", 300, 300)), "pressed into the menu bar, moving left selects the top-left quarter")
p.f = home
dragPath(p, { { 1000, 50 }, { 1080, 100 } })
check(same(p.f, hotkeyFrame("topRight", 300, 300)), "the top row's right cell tiles the top-right quarter")
p.f = home
_, panel = dragPath(p, { { 1000, 1 }, { 1000, 120 } })
check(not panel and p.f.w == 800, "below the top row the panel closes and nothing drops")

p.f = home
_, panel = dragPath(p, { { 1000, 1328 } })
check(panel and labelOf(preview.picker) == "Bottom half", "the bottom edge shows a row with the bottom half in the middle")
p.f = home
dragPath(p, { { 1000, 1328 }, { 960, 1328 } })
check(same(p.f, hotkeyFrame("bottomLeft", 300, 300)), "moving left along the bottom selects the bottom-left quarter")
p.f = home
dragPath(p, { { 1000, 1328 }, { 1060, 1270 } })
check(same(p.f, hotkeyFrame("bottomRight", 300, 300)), "the bottom row's right cell tiles the bottom-right quarter")
check(labelOf(preview.picker) == "Bottom right", "with its label")

-- Grabbed 37 pt below its top, as at the bottom of Ghostty's title bar, a window
-- pinned against the 39 pt menu bar holds the cursor at y 76. That counts as the top
-- edge without pushing the cursor up through the title bar.
p.f = home
_, panel = dragPath(p, { { 1000, 76 } }, false, 37)
check(panel and same(p.f, LEFT), "a window pinned against the menu bar counts as the top edge and maximizes")
p.f = home
dragPath(p, { { 1000, 78 } }, false, 37)
check(same(p.f, LEFT), "within 3 pt of pinned still counts")
p.f = home
_, panel = dragPath(p, { { 1000, 80 } }, false, 37)
check(not panel and p.f.w == 800, "a window held just below the menu bar does not")
p.f = home
_, panel = dragPath(p, { { 1000, 76 } }, false, 10)
check(not panel and p.f.w == 800, "grabbed 10 pt down, the same cursor height is 37 pt below the menu bar and does not count")
p.f = home
dragPath(p, { { 1000, 76 }, { 940, 76 } }, false, 37)
check(same(p.f, hotkeyFrame("topLeft", 300, 300)), "pinned, the top row's cells select as usual")
p.f = home
dragPath(p, { { 3000, 30 + 37 } }, false, 37)
check(same(p.f, RIGHT), "on the external screen, pinned under its 30 pt menu bar")

-- The corner zones are 7.5% of each edge, 154 pt along the left screen's top and 97
-- pt along its sides. Just past them the panel shows.
p.f = home
_, panel = dragPath(p, { { 200, 1 } })
check(panel and labelOf(preview.picker) == "Maximize", "200 pt from the corner along the top shows the panel")
p.f = home
_, panel = dragPath(p, { { 1, 39 + 120 } })
check(panel and labelOf(preview.picker) == "Left side", "120 pt down the left edge shows the panel")
p.f = home
_, panel = dragPath(p, { { 1, 39 + 40 } })
check(panel and labelOf(preview.picker) == "Top left" and same(p.f, hotkeyFrame("topLeft", 300, 300)),
  "40 pt down is the corner zone, which opens the L on its corner cell")

-- The L in the bottom-left corner of the left screen. Its column runs up the left
-- edge, x 4 to 82 and y 1139 to 1325, with cells at y 1146, 1205, and 1264. Its row
-- runs along the bottom, x 4 to 220 and y 1257 to 1325, with cells at x 11, 80, and
-- 149. The bottom-left cell at 11,1264 is the one they share.
p.f = home
local _, lShown = dragPath(p, { { 1, 1328 } })
check(lShown and labelOf(preview.picker) == "Bottom left", "flung into the corner, the L opens on the shared corner cell")
check(same(p.f, hotkeyFrame("bottomLeft", 300, 300)), "and releasing there tiles the bottom-left quarter")
local L = drag.panel.layoutCorner("bottomLeft", LEFT, LEFT_FULL)
check(#L.cells == 5 and #L.panels == 2, "the L has five cells on two panels")
check(L.cells[L.arms[1].cells[3]] == L.cells[L.arms[2].cells[1]], "the column's bottom cell is the row's left cell")
check(same(L.cells[L.shared].rect, { x = 11, y = 1264, w = 64, h = 54 }), "the shared cell sits in the corner")

p.f = home
dragPath(p, { { 1, 1328 }, { 110, 1328 } })
check(same(p.f, hotkeyFrame("down", 300, 300)), "sliding right along the bottom arm selects the bottom half")
p.f = home
dragPath(p, { { 1, 1328 }, { 200, 1328 } })
check(same(p.f, hotkeyFrame("bottomRight", 300, 300)), "and further right, still on the row, the bottom-right quarter")
p.f = home
local _, followed = dragPath(p, { { 1, 1328 }, { 300, 1328 } })
check(followed and labelOf(preview.picker) == "Bottom half" and same(p.f, hotkeyFrame("down", 300, 300)),
  "past the row's end the side is selected")

-- Leaving the L along its row keeps the row where it was as a straight panel, x 4,
-- drops the column, and the magnet pulls it on to 16 pt behind the cursor
drag.pickerFollow = 0.08
p.f = home
focused = p
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
p.f = { x = home.x - 599, y = home.y + 1118, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1328))
drag:_stopAnim()
local rowCanvas = drag.target.picker.panels[2]
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 300, 1328))
local row = drag.target.picker
check(not row.corner and row.side == "bottom", "past the row's end the L becomes the bottom row alone")
check(row.rect.x == 300 - 16 - row.rect.w, "pulled so its right end trails the cursor by 16 pt, at x " .. row.rect.x)
local aligned = drag.panel.layout("bottom", LEFT, LEFT_FULL, { x = 300, y = 1328 })
drag.panel.alignTo(aligned, drag.panel.layoutCorner("bottomLeft", LEFT, LEFT_FULL))
check(aligned.rect.x == rowCanvas.x and math.abs(preview.picker:frame().x - aligned.canvasFrame.x) < 2,
  "drawn from where the L's row was, not centered on the cursor, canvas at x " .. preview.picker:frame().x)
check(drag.anims[preview.picker] and drag.anims[preview.picker].follow == row, "and easing after the cursor from there")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 300, 1328))
drag:_stopAnim()

-- On a 1x screen the canvas rounds its frame to whole points, and the glide still
-- arrives, so the L is drawn
ROUND_FRAMES = true
drag.pickerFollow = 0.08
p.f = home
focused = p
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
p.f = { x = home.x - 599, y = home.y + 390, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 600))
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1328))
local rounded = drag.target.morph
for _ = 1, 200 do
  local a = drag.anims[preview.picker]
  if not a then break end
  a.start, a.last = a.start - 16e6, (a.last or a.start) - 16e6
  drag:_animTick()
end
check(rounded and rounded.arrived and labelOf(preview.picker) == "Bottom left" and #preview.picker.els > 12,
  "with whole-point frames the glide still arrives and the L is drawn")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 1, 1328))
drag:_stopAnim()
ROUND_FRAMES = false
drag.pickerFollow = 0

-- Leaving it up the column does the same with the left column
p.f = home
focused = p
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
p.f = { x = home.x - 599, y = home.y + 1118, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1328))
drag:_stopAnim()
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1000))
local col = drag.target.picker
check(not col.corner and col.side == "left" and col.rect.y == 1000 + 16,
  "past the column's top the L becomes the left column, pulled to 16 pt below the cursor")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 1, 1000))
drag:_stopAnim()
drag.pickerFollow = 0
p.f = home
dragPath(p, { { 1, 1328 }, { 1, 1230 } })
check(same(p.f, hotkeyFrame("left", 300, 300)), "sliding up the column selects the left half")
p.f = home
dragPath(p, { { 1, 1328 }, { 1, 1170 } })
check(same(p.f, hotkeyFrame("topLeft", 300, 300)), "and further up the top-left quarter")
p.f = home
_, lShown = dragPath(p, { { 1, 1328 }, { 1, 1230 }, { 110, 1328 } })
check(lShown and labelOf(preview.picker) == "Bottom half", "the L passes from the column to the row without closing")
p.f = home
_, lShown = dragPath(p, { { 1, 1328 }, { 400, 900 } })
check(not lShown and p.f.w == 800, "leaving both arms closes the L and drops nothing")

-- Every panel's canvas reaches past it, so the outline stroked on its edge is not clipped
local dp = drag.panel
local roomy = true
for _, pk in ipairs({ dp.layout("left", LEFT, LEFT_FULL, { x = 1, y = 600 }), dp.layout("right", RIGHT, RIGHT_FULL, { x = 4100, y = 600 }),
    dp.layout("top", LEFT, LEFT_FULL, { x = 1000, y = 1 }), dp.layout("bottom", LEFT, LEFT_FULL, { x = 1000, y = 1328 }),
    dp.layoutCorner("bottomLeft", LEFT, LEFT_FULL), dp.layoutCorner("topRight", RIGHT, RIGHT_FULL) }) do
  local c = pk.canvasFrame
  for _, panel in ipairs(pk.panels) do
    if panel.x - c.x < 2 or panel.y - c.y < 2 or c.x + c.w - panel.x - panel.w < 2 or c.y + c.h - panel.y - panel.h < 2 then
      roomy = false
    end
  end
end
check(roomy, "every panel's canvas leaves 2 pt around it for the outline")

-- An L's background is one outline of its shape, so no border is drawn twice
local fake = { replaceElements = function(self, els) self.els = els end, frame = function() end }
for _, corner in ipairs({ "topLeft", "topRight", "bottomLeft", "bottomRight" }) do
  local lp = dp.layoutCorner(corner, LEFT, LEFT_FULL)
  dp.render(fake, lp, nil)
  local bg, inBounds = fake.els[1], true
  for _, pt in ipairs(bg.coordinates or {}) do
    if pt.x < 0 or pt.y < 0 or pt.x > lp.canvasFrame.w or pt.y > lp.canvasFrame.h then inBounds = false end
  end
  local panelRects = 0
  for _, el in ipairs(fake.els) do
    if el.type == "rectangle" and el.roundedRectRadii and el.roundedRectRadii.xRadius == 15 then panelRects = panelRects + 1 end
  end
  check(bg.type == "segments" and bg.closed and #bg.coordinates == 13 and inBounds and panelRects == 0,
    "the " .. corner .. " L is one closed outline with six rounded corners inside its canvas")
end
dp.render(fake, dp.layout("left", LEFT, LEFT_FULL, { x = 1, y = 600 }), nil)
check(fake.els[1].type == "rectangle", "a straight panel is still one rounded rectangle")

-- The top-right L on the right screen shares its top-right cell, with Maximize in its row
local TR = drag.panel.layoutCorner("topRight", RIGHT, RIGHT_FULL)
check(TR.cells[TR.shared].position == "topRight" and TR.cells[TR.arms[2].cells[2]].position == "maximize",
  "the top-right L shares top right and offers maximize along the top")
p.f = home
dragPath(p, { { 4102, 32 }, { 4102 - 100, 32 } })
check(same(p.f, RIGHT), "sliding left along its top arm maximizes, got " .. show(p.f))

-- Leaving the edge and coming straight back shows the panel again, fully opaque
p.f = home
local _, back, alpha = dragPath(p, { { 1, 600 }, { 300, 600 }, { 1, 600 } })
check(back and alpha == 1, "the panel comes back opaque after leaving and returning, alpha " .. tostring(alpha))

-- Along the edge a panel selects only within its own length, y 507 to 693 here.
-- Past either end the side is selected, and more than 16 pt past it the panel is
-- pulled along so that end trails the cursor by 16 pt.
p.f = home
dragPath(p, { { 1, 600 }, { 1, 690 } })
check(same(p.f, hotkeyFrame("bottomLeft", 300, 300)), "within the panel, its bottom cell selects")
p.f = home
local _, again = dragPath(p, { { 1, 600 }, { 1, 800 } })
check(again and labelOf(preview.picker) == "Left side" and same(p.f, hotkeyFrame("left", 300, 300)),
  "sliding down past the panel selects the side, not the bottom corner")
p.f = home
dragPath(p, { { 1, 600 }, { 1, 800 }, { 1, 760 } })
check(same(p.f, hotkeyFrame("bottomLeft", 300, 300)),
  "pulled down to 784, the panel's bottom cell is the first one met coming back up")
-- The pull: the panel's cells move at once, and its drawing eases after them, a
-- share of the way each frame
drag.pickerFollow, drag.cornerPull = 0.08, 0.04
p.f = home
focused = p
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
p.f = { x = home.x - 599, y = home.y + 390, w = 800, h = 600 }
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 600))
local before = preview.picker:frame()
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 800))
local follow = drag.anims[preview.picker]
check(follow and follow.follow == drag.target.picker, "pulling the panel starts its drawing easing after it")
check(drag.target.picker.rect.y == 598, "with its cells already where the pull puts them, bottom 16 pt above the cursor, panel at y " .. drag.target.picker.rect.y)
local mid = preview.picker:frame()
check(mid.y >= before.y and mid.y < before.y + 200, "the drawing has not jumped there")
-- In the corner zone the straight panel glides on into its place in the L, which
-- is drawn once it arrives. The bottom-left L's column starts at y 1139.
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1, 1328))
local morph = drag.target.morph
check(morph and morph.to == drag.target.picker and morph.to.corner == "bottomLeft",
  "reaching the corner zone makes the L the active panel")
check(morph.from.rect.y == 1139, "and moves the straight panel to the L's column, at y " .. morph.from.rect.y)
local glide = drag.anims[preview.picker]
check(glide and glide.follow == morph.from and glide.tau == 0.04 and labelOf(preview.picker) == "Bottom left" and #preview.picker.els < 12,
  "whose drawing is pulled there twice as hard as the follow, still the straight panel, with its Bottom left lit")
local litBL = false
for _, el in ipairs(preview.picker.els) do
  if el.type == "rectangle" and el.fillColor and el.fillColor.alpha == 0.25 then litBL = el.frame.y + preview.picker:frame().y end
end
check(litBL and math.abs(litBL - morph.from.cells[3].rect.y) < 1 + math.abs(preview.picker:frame().y - morph.from.canvasFrame.y),
  "its bottom cell is the one lit")
glide.start, glide.last = glide.start - 5e9, glide.last and glide.last - 5e9
drag:_animTick()
check(morph.arrived and #preview.picker.els > 12 and labelOf(preview.picker) == "Bottom left",
  "on arrival the L is drawn in its place, with its label")
check(math.abs(preview.picker:frame().y - morph.to.canvasFrame.y) < 1, "on the L's own canvas frame")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 1, 1328))
check(same(p.f, hotkeyFrame("bottomLeft", 300, 300)), "and releasing tiles the bottom-left quarter")
drag:_stopAnim()
drag.pickerFollow, drag.cornerPull = 0, 0

p.f = home
_, again = dragPath(p, { { 1, 600 }, { 60, 800 } })
check(again and same(p.f, hotkeyFrame("left", 300, 300)), "anywhere in the strip, even past the old end, the panel follows")

-- The Mission Control guard. Pressed against the top of the left screen, a jerk up
-- of more than 25 pt is moved to y 1, and so is anything there for 0.25 s after.
p.f = home
focused = p
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
p.f = { x = home.x + 400, y = home.y - 209, w = 800, h = 600 }
local mc = event(hs.eventtap.event.types.leftMouseDragged, 1000, 0, -10)
drag:_onDrag(mc)
check(mc:location().y == 0, "reaching the top is left alone")
mc = event(hs.eventtap.event.types.leftMouseDragged, 1000, 0, -30)
drag:_onDrag(mc)
check(mc:location().y == 1, "a jerk up of 30 pt held at the top is moved 1 pt down")
mc = event(hs.eventtap.event.types.leftMouseDragged, 1000, 0, -5)
drag:_onDrag(mc)
check(mc:location().y == 0, "the next event is judged from the moved y 1, as Rectangle does, and passes")
drag.dragPrevY = 0
mc = event(hs.eventtap.event.types.leftMouseDragged, 1000, 0, -5)
drag:_onDrag(mc)
check(mc:location().y == 1, "within 0.25 s of a jerk, a gentle push at the top is held down too")
drag.guardUntil, drag.dragPrevY = 0, 0
mc = event(hs.eventtap.event.types.leftMouseDragged, 1000, 0, -5)
drag:_onDrag(mc)
check(mc:location().y == 0, "after the window, a gentle push reaches the top")
check(labelOf(preview.picker) == "Maximize", "and the top edge's panel is up throughout")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 1000, 1))
check(same(p.f, LEFT), "releasing there still maximizes")
drag.missionControlGuard = false
p.f = home
focused = p
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 210))
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1000, 0, -10))
mc = event(hs.eventtap.event.types.leftMouseDragged, 1000, 0, -30)
drag:_onDrag(mc)
check(mc:location().y == 0, "with the guard off nothing is moved")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 1000, 0))
drag.missionControlGuard = true

-- The magnet: within 16 pt past the end nothing moves, beyond it the panel is pulled,
-- and coming back toward it leaves it where it was pulled to
local mp = dp.layout("left", LEFT, LEFT_FULL, { x = 1, y = 600 })
check(not dp.magnet(mp, { x = 1, y = 693 + 16 }, 16) and mp.rect.y == 507, "16 pt past the bottom the panel stays")
check(dp.magnet(mp, { x = 1, y = 750 }, 16) and mp.rect.y + mp.rect.h == 734, "past that its bottom is pulled to 16 pt above the cursor")
check(not dp.magnet(mp, { x = 1, y = 700 }, 16) and mp.rect.y + mp.rect.h == 734, "moving back up leaves it there")
check(not dp.magnet(mp, { x = 1, y = 548 + 1 }, 16) and mp.rect.y == 548, "up to 16 pt past its top it still stays")
check(dp.magnet(mp, { x = 1, y = 500 }, 16) and mp.rect.y == 516, "and beyond that it is pulled the other way")
check(mp.cells[1].rect.y == mp.rect.y + 7 and mp.arms[1].span[1] == mp.rect.y, "its cells and span move with it")

-- Each screen is a box whose corners reach 144 pt along both edges, measured from
-- the usable frame, so below the menu bar at the top, whatever the screen's size and
-- whether or not an edge is shared. Left screen usable 0,39 2056x1290, right screen
-- usable 2056,30 2048x1250.
drag.dragScreens = {}
for _, sc in ipairs(screens) do
  drag.dragScreens[#drag.dragScreens + 1] = { screen = sc, full = sc:fullFrame(), frame = sc:frame() }
end
local function corner(x, y) local _, pos = drag:_zoneAt({ x = x, y = y }) return pos end
local reach = {
  { 1, 39 + 143, "topLeft" }, { 1, 39 + 145, "left" },
  { 1, 1329 - 143, "bottomLeft" }, { 1, 1329 - 145, "left" },
  { 143, 1328, "bottomLeft" }, { 145, 1328, "down" },
  { 2056 - 143, 1328, "bottomRight" }, { 2056 - 145, 1328, "down" },
  { 143, 40, "topLeft" }, { 145, 40, "maximize" },
  { 2055, 39 + 143, "topRight" }, { 2055, 39 + 145, "right" },
  { 2056 + 143, 31, "topLeft" }, { 2056 + 145, 31, "maximize" },
  { 4103, 1280 - 143, "bottomRight" }, { 4103, 1280 - 145, "right" },
  { 4104 - 143, 1279, "bottomRight" }, { 4104 - 145, 1279, "down" },
}
local uniform = true
for _, r in ipairs(reach) do
  if corner(r[1], r[2]) ~= r[3] then
    uniform = false
    print("  at " .. r[1] .. "," .. r[2] .. " got " .. tostring(corner(r[1], r[2])) .. ", wanted " .. r[3])
  end
end
check(uniform, "every corner of both screens reaches 144 pt along both of its edges, shared or not")
drag.cornerZone = 1000
check(corner(1, 39 + 600) == "topLeft" and corner(1, 39 + 700) == "bottomLeft",
  "a reach past half an edge is capped there, so the two corners split the edge")
drag.cornerZone = 144
drag.dragScreens = nil

-- A row near a screen's side is kept on screen
local row = drag.panel.layout("bottom", LEFT, LEFT_FULL, { x = 20, y = 1328 })
check(row.rect.x == 4, "a row opened near the left side starts 4 pt in, got " .. row.rect.x)

-- Stacked screens: the shared edge is the upper screen's bottom edge
screens = { fakeScreen(1, LEFT_FULL, LEFT), fakeScreen(3, { x = 0, y = 1329, w = 2056, h = 1329 },
  { x = 0, y = 1329, w = 2056, h = 1329 }) }
tiler, gb, drag = boot()
order = {}
local c = fakeWindow(3, { x = 400, y = 200, w = 800, h = 600 })
local cHome = c:frame()
dragTo(c, 1000, 1328)
check(same(c.f, hotkeyFrame("down", 300, 300)), "the edge between stacked screens tiles the upper one's bottom half")
c.f = { x = 400, y = 1500, w = 800, h = 600 }
local _, lowerPanel = dragPath(c, { { 1000, 1329 + 37 } }, false, 37)
check(not lowerPanel and c.f.w == 800, "on a screen with another above it, pinning near the top does not count")
c.f = { x = 400, y = 1500, w = 800, h = 600 }
focused = c
drag:_onClick(event(hs.eventtap.event.types.leftMouseDown, 600, 1510))
drag:_onDrag(event(hs.eventtap.event.types.leftMouseDragged, 1000, 1329, -10))
local up = event(hs.eventtap.event.types.leftMouseDragged, 1000, 1329, -30)
drag:_onDrag(up)
check(up:location().y == 1329, "the guard leaves a top edge with a screen above alone, so the drag can cross")
drag:_onClick(event(hs.eventtap.event.types.leftMouseUp, 1000, 1329))
drag.seams = false
c.f = cHome
dragTo(c, 1000, 1328)
check(c.f.w == 800 and c.f.h == 600, "and with seams off it does not tile")
drag.seams = true

-- Stopping releases the tap, the timers, and the preview
local canvas, pickerCanvas = preview.canvas, preview.picker
drag:stop()
check(canvas.deleted and pickerCanvas.deleted and require("CaddieCore").titlebar().clickTap == nil,
  "stop deletes the preview and the panel and unsubscribes from the shared click tap")

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
