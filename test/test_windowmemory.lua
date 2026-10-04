-- Run: lua test/test_windowmemory.lua   (from the repo root)
-- WindowState's memory with the real Core, TileManager, and TitleBarTweaks, presets and
-- gap set as in the profile, through the edge cases in docs/window-memory.md.
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

-- The owner's example: an ultrawide, and a small screen to its right
local WIDE = { x = 0, y = 0, w = 3440, h = 1440 }
local SMALL = { x = 3440, y = 0, w = 1000, h = 1000 }

local screens = {}
local function fakeScreen(id, frame)
  return { id = function() return id end, frame = function() return frame end }
end
local function screenOf(f)
  local cx, cy = f.x + f.w / 2, f.y + f.h / 2
  for _, s in ipairs(screens) do
    local r = s:frame()
    if cx >= r.x and cx < r.x + r.w and cy >= r.y and cy < r.y + r.h then return s end
  end
  return screens[1]
end

local alive = {}
local function fakeWindow(id, bundle, frame)
  local w = { _id = id, f = frame }
  alive[id] = w
  function w:id() return self._id end
  function w:frame() return { x = self.f.x, y = self.f.y, w = self.f.w, h = self.f.h } end
  function w:setFrame(r) self.f = { x = r.x, y = r.y, w = r.w, h = r.h } end
  function w:screen() return screenOf(self.f) end
  function w:focus() end
  function w:application()
    return {
      bundleID = function() return bundle end,
      findMenuItem = function() return nil end,
      selectMenuItem = function() return false end,
    }
  end
  return w
end

-- A fresh Hammerspoon over the same settings store, which survives the "restart"
local store = {}
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function boot()
  for name in pairs(package.loaded) do
    if name:match("^%u%a+$") then
      package.loaded[name] = nil
    end
  end
  stub.install(".")
  hs.screen.allScreens = function() return screens end
  hs.screen.watcher.new = function() return { start = function(s) return s end, stop = function() end } end
  hs.settings = {
    get = function(k) return copy(store[k]) end,
    set = function(k, v) store[k] = copy(v) end,
  }
  hs.window.list = function()
    local out = {}
    for id in pairs(alive) do out[#out + 1] = { kCGWindowNumber = id } end
    return out
  end
  hs.timer.usleep = function() end
  local state = stub.loadSpoon("CaddieCore"):start().window()
  state.gap = 1
  state.presets = { ["com.apple.Terminal"] = { w = 0.6, h = 0.7 } }
  local tiler = stub.loadSpoon("TileManager")
  local gb = stub.loadSpoon("TitleBarTweaks")
  return tiler, gb, state.memory
end

screens = { fakeScreen(1, WIDE), fakeScreen(2, SMALL) }
local tiler, gb, memory = boot()

-- Row 1: natural, maximize by hotkey, green button
local natural = { x = 100, y = 100, w = 800, h = 600 }
local a = fakeWindow(1, "com.example.a", natural)
tiler:maximize(a)
check(same(a.f, WIDE), "hotkey maximize fills the screen with no gap")
local r = gb:toggle(a)
check(r.mode == "restore" and same(a.f, natural), "row 1: green button after the hotkey restores the natural frame, got " .. show(a.f))
check(memory.entries[1] == nil, "a restore forgets the entry")

-- Row 2: a chain keeps the first natural frame
tiler:tile("left", a)
tiler:tile("right", a)
tiler:maximize(a)
r = gb:toggle(a)
check(r.mode == "restore" and same(a.f, natural), "row 2: left, right, maximize, then green restores the natural frame, got " .. show(a.f))

-- Row 6: after a restore the green button maximizes again
r = gb:toggle(a)
check(r.mode == "maximize" and same(a.f, WIDE), "row 6: green after a restore maximizes again")
r = gb:toggle(a)
check(r.mode == "restore" and same(a.f, natural), "and the next click restores again")

-- Row 4: maximized on the ultrawide, cycled to the small screen, restored there by
-- free-space fraction. 3000 / 3040 * 600 = 592.1, 1000 / 1040 * 600 = 576.9.
local b = fakeWindow(2, "com.example.b", { x = 3000, y = 1000, w = 400, h = 400 })
tiler:maximize(b)
tiler:maximize(b)
check(same(b.f, SMALL), "maximize again moves to the small screen, maximized")
r = gb:toggle(b)
check(same(b.f, { x = 3440 + 592, y = 577, w = 400, h = 400 }),
  "row 4: restore on another screen keeps the edge distance by free space, got " .. show(b.f))

-- Row 5: larger than the small screen on both axes. 2000 / 3440 * 1000 = 581.4 and
-- 1200 / 1440 * 1000 = 833.3, then x = 200 / 1440 * 419 = 58.2, y = 100 / 240 * 167 = 69.6.
local c = fakeWindow(3, "com.example.c", { x = 200, y = 100, w = 2000, h = 1200 })
tiler:maximize(c)
tiler:maximize(c)
gb:toggle(c)
check(same(c.f, { x = 3440 + 58, y = 70, w = 581, h = 833 }),
  "row 5: an oversized window keeps its screen fraction and stays on screen, got " .. show(c.f))

-- Row 8: two windows of one app keep separate memories
local d1 = fakeWindow(4, "com.google.Chrome", { x = 10, y = 20, w = 500, h = 400 })
local d2 = fakeWindow(5, "com.google.Chrome", { x = 900, y = 300, w = 700, h = 500 })
tiler:tile("left", d1)
tiler:maximize(d1)
tiler:maximize(d2)
gb:toggle(d1)
gb:toggle(d2)
check(same(d1.f, { x = 10, y = 20, w = 500, h = 400 }) and same(d2.f, { x = 900, y = 300, w = 700, h = 500 }),
  "row 8: two windows of one app each restore to their own natural frame")

-- Preset: the presets rule maximizes Terminal to 60% by 70%, which geometry alone would
-- not recognize as maximized. The entry's kind does.
local t = fakeWindow(6, "com.apple.Terminal", { x = 50, y = 60, w = 600, h = 400 })
tiler:maximize(t)
check(not same(t.f, WIDE), "Terminal maximizes to its preset")
r = gb:toggle(t)
check(r.mode == "restore" and same(t.f, { x = 50, y = 60, w = 600, h = 400 }),
  "a preset maximize is still restored by the green button")
r = gb:toggle(t)
local hotkeyPreset = { x = t.f.x, y = t.f.y, w = t.f.w, h = t.f.h }
gb:toggle(t)
tiler:maximize(t)
check(r.mode == "maximize" and same(hotkeyPreset, t.f), "the green-button maximize equals the hotkey's preset frame")
gb:toggle(t)

-- Row 10: moved by hand since the maximize, so the entry is not trusted
local e = fakeWindow(7, "com.example.e", { x = 400, y = 300, w = 900, h = 700 })
tiler:maximize(e)
e.f = { x = 50, y = 50, w = 600, h = 400 }
r = gb:toggle(e)
check(r.mode == "maximize" and same(e.f, WIDE), "row 10: a hand-moved window maximizes rather than restoring stale memory")
r = gb:toggle(e)
check(r.mode == "restore" and same(e.f, { x = 50, y = 50, w = 600, h = 400 }), "and its hand-placed frame is the new natural frame")

-- Row 10, the maximized-looking variant, and row 13: no trusted memory and no menu
tiler:maximize(e)
e.f = { x = 2, y = 2, w = 3436, h = 1436 }
r = gb:toggle(e)
check(r.mode == "restore" and r.method == "default" and same(e.f, { x = 573, y = 240, w = 2293, h = 960 }),
  "row 13: a maximized window with no trusted memory restores to two thirds centered, got " .. show(e.f))

-- Rows 14 and 15: macOS moves a window on undock, then puts it back on redock
local u = fakeWindow(8, "com.example.u", { x = 600, y = 200, w = 1000, h = 800 })
tiler:maximize(u)
local applied = { x = u.f.x, y = u.f.y, w = u.f.w, h = u.f.h }
u.f = { x = 3440, y = 0, w = 1000, h = 1000 }
check(memory:trusted(8, u:frame()) == nil and memory.entries[8] ~= nil, "row 14: moved by macOS, the entry is dormant but kept")
u.f = applied
r = gb:toggle(u)
check(r.mode == "restore" and same(u.f, { x = 600, y = 200, w = 1000, h = 800 }), "row 15: back where we left it, the entry is trusted again")

-- Row 16: moved by hand after tiling, then tiled again
local h = fakeWindow(9, "com.example.h", { x = 100, y = 100, w = 400, h = 300 })
tiler:tile("left", h)
h.f = { x = 300, y = 300, w = 500, h = 500 }
tiler:tile("right", h)
tiler:maximize(h)
gb:toggle(h)
check(same(h.f, { x = 300, y = 300, w = 500, h = 500 }), "row 16: the hand-placed frame replaces the old natural frame")

-- Row 12: a window already in a tile when first seen is never given a tiled natural frame
local g = fakeWindow(10, "com.example.g", { x = 0, y = 0, w = 1720, h = 1440 })
tiler:tile("right", g)
check(memory.entries[10] and memory.entries[10].original == nil, "row 12: a tiled-looking frame is not recorded as natural")
tiler:maximize(g)
r = gb:toggle(g)
check(r.mode == "restore" and r.method == "default", "and its restore falls back")

-- Rows 9 and 11: memory survives a restart, then a chain continues from it
local k = fakeWindow(11, "com.example.k", { x = 700, y = 400, w = 1100, h = 650 })
tiler:maximize(k)
local dead = fakeWindow(99, "com.example.dead", { x = 0, y = 0, w = 300, h = 300 })
tiler:maximize(dead)
alive[99] = nil
tiler, gb, memory = boot()
check(memory.entries[11] ~= nil and memory.entries[99] == nil, "after a restart the entry is loaded and closed windows are pruned")
tiler:tile("right", k)
tiler:maximize(k)
r = gb:toggle(k)
check(r.mode == "restore" and same(k.f, { x = 700, y = 400, w = 1100, h = 650 }),
  "row 11: after a restart, tiling again keeps the natural frame from before the first maximize, got " .. show(k.f))
tiler:maximize(k)
tiler, gb, memory = boot()
gb:toggle(k)
check(same(k.f, { x = 700, y = 400, w = 1100, h = 650 }), "row 9: maximized, reloaded, green restores")

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
