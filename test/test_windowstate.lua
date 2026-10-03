-- Run: lua test/test_windowstate.lua   (from the repo root)
-- WindowState on its own: place, restore, and undo, the placement rules, memory
-- across a restart, and middleware from another owner.
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

local SF = { x = 0, y = 0, w = 2000, h = 1000 }
local OTHER = { x = 2000, y = 0, w = 1000, h = 800 }
local screens = {}

local function fakeScreen(id, frame)
  return { id = function() return id end, frame = function() return frame end }
end

local alive = {}
local function fakeWindow(id, bundle, frame)
  local w = { _id = id, f = frame, sets = 0 }
  alive[id] = w
  function w:id() return self._id end
  function w:frame() return { x = self.f.x, y = self.f.y, w = self.f.w, h = self.f.h } end
  function w:setFrame(r) self.f = { x = r.x, y = r.y, w = r.w, h = r.h } self.sets = self.sets + 1 end
  function w:screen() return screens[1] end
  function w:application() return { bundleID = function() return bundle end } end
  return w
end

local store = {}
local function boot()
  for name in pairs(package.loaded) do
    if name:match("^%u%a+$") then package.loaded[name] = nil end
  end
  stub.install(".")
  hs.screen.allScreens = function() return screens end
  hs.settings = {
    get = function(k) return store[k] end,
    set = function(k, v) store[k] = v end,
  }
  hs.window.list = function()
    local out = {}
    for id in pairs(alive) do out[#out + 1] = { kCGWindowNumber = id } end
    return out
  end
  local Core = stub.loadSpoon("CaddieCore")
  return Core, Core.window()
end

screens = { fakeScreen(1, SF), fakeScreen(2, OTHER) }
local Core, state = boot()
check(Core.window() == state, "Core.window() returns one shared instance")

local half = { x = 0, y = 0, w = 1000, h = 1000 }

-- place applies the frame and reports where the window was
local natural = { x = 100, y = 100, w = 600, h = 400 }
local a = fakeWindow(1, "com.example.a", natural)
local events = {}
state:on("*", function(p, name) events[#events + 1] = { name = name, p = p } end, "test")
local r = state:place(a, { kind = "tile", position = "left", frame = half, screenFrame = SF, source = "tile" })
check(r.status == "completed" and same(a.f, half), "place applies the frame")
check(same(r.previousFrame, natural) and same(r.finalFrame, half), "the result carries the frames before and after")
local ev = events[#events]
check(ev.name == "place.completed" and ev.p.source == "tile" and ev.p.kind == "tile" and ev.p.position == "left",
  "the event names its source, kind, and position")

-- restore returns the natural frame and forgets the entry
r = state:restore(a, { source = "titlebar" })
check(r.status == "completed" and r.mode == "restore" and same(a.f, natural), "restore returns the natural frame, got " .. show(a.f))
check(state.memory.entries[1] == nil, "a restore forgets the entry")
r = state:restore(a)
check(r.status == "unchanged" and r.reason == "no natural frame", "with nothing remembered and no fallback, restore is unchanged")

-- A fallback decides when memory has nothing
r = state:restore(a, { fallback = function(win) return "default", { x = 5, y = 5, w = 50, h = 50 } end })
check(r.method == "default" and same(r.finalFrame, { x = 5, y = 5, w = 50, h = 50 }), "the caller's fallback runs when memory has nothing")

-- A chain of placements keeps the first natural frame, and undo walks back
local b = fakeWindow(2, "com.example.b", { x = 300, y = 200, w = 500, h = 500 })
state:place(b, { kind = "tile", position = "left", frame = half, screenFrame = SF })
state:place(b, { kind = "maximize", position = "maximize", frame = SF, screenFrame = SF })
r = state:undo(b)
check(r.status == "completed" and same(b.f, half), "undo returns the frame before the last placement")
r = state:undo(b)
check(same(b.f, { x = 300, y = 200, w = 500, h = 500 }), "and the one before that")
r = state:undo(b)
check(r.status == "unchanged" and r.reason == "nothing to undo", "an empty stack is unchanged")

-- Rules: gap, flush sides stay flush
state.gap = 4
state:place(b, { kind = "tile", position = "left", frame = half, screenFrame = SF })
check(same(b.f, { x = 0, y = 0, w = 996, h = 1000 }), "the gap insets only the side not on the screen edge, got " .. show(b.f))
state:place(b, { kind = "maximize", position = "maximize", frame = SF, screenFrame = SF })
check(same(b.f, SF), "a maximize has no gap")
local moved = { x = 2004, y = 0, w = 496, h = 800 }
state:place(b, { kind = "move", frame = moved, screenFrame = OTHER })
check(same(b.f, moved), "a move keeps the frame it was given, gap untouched")
state.gap = 0

-- Rules: presets and center-small, by app
state.presets = { ["com.example.term"] = { w = 0.5, h = 0.5 } }
state.centerSmall = { fraction = 0.5, apps = { ["com.example.calc"] = true } }
local t = fakeWindow(3, "com.example.term", { x = 10, y = 10, w = 100, h = 100 })
state:place(t, { kind = "maximize", position = "maximize", frame = SF, screenFrame = SF })
check(same(t.f, { x = 500, y = 250, w = 1000, h = 500 }), "a preset sizes the maximize, got " .. show(t.f))
state:place(t, { kind = "tile", position = "left", frame = half, screenFrame = SF })
check(same(t.f, half), "a preset leaves tiles alone")
local c = fakeWindow(4, "com.example.calc", { x = 10, y = 10, w = 100, h = 100 })
state:place(c, { kind = "tile", position = "left", frame = half, screenFrame = SF })
check(same(c.f, { x = 250, y = 250, w = 500, h = 500 }), "center-small shrinks a tile, got " .. show(c.f))

-- Rules: minimum size and exclusions veto, naming WindowState
state.minSize = { w = 600, h = 300 }
r = state:place(c, { kind = "tile", position = "left", frame = half, screenFrame = SF })
check(r.status == "vetoed" and r.by == "WindowState" and r.reason:find("below minimum", 1, true), "the minimum size vetoes a shrunken tile")
state.minSize = nil
state.excluded = { ["com.example.calc"] = true }
local before = c.sets
r = state:place(c, { kind = "maximize", position = "maximize", frame = SF, screenFrame = SF })
check(r.status == "vetoed" and r.reason == "excluded app com.example.calc" and c.sets == before, "an excluded app is never moved")
check(r.windowID == 4 and r.app == "com.example.calc", "a vetoed result still names the window")
r = state:undo(c)
check(r.status == "vetoed", "undo is vetoed for an excluded app too")
state.excluded = nil

-- Another owner's middleware, filtering on source
local unhook = state:use("place", function(ctx)
  if ctx.input.source == "snap" then return false, "no snapping here" end
end, { kind = "guard", owner = "Mine", name = "nosnap" })
r = state:place(a, { kind = "tile", position = "right", frame = { x = 1000, y = 0, w = 1000, h = 1000 }, screenFrame = SF, source = "snap" })
check(r.status == "vetoed" and r.by == "Mine", "another owner's guard can veto by source")
r = state:place(a, { kind = "tile", position = "right", frame = { x = 1000, y = 0, w = 1000, h = 1000 }, screenFrame = SF, source = "tile" })
check(r.status == "completed", "and lets other sources through")
unhook()

-- previousFrame from the caller wins, as for an edge drop mid-drag
local d = fakeWindow(5, "com.example.d", { x = 900, y = 600, w = 400, h = 300 })
state:place(d, { kind = "tile", position = "left", frame = half, screenFrame = SF, previousFrame = { x = 50, y = 60, w = 400, h = 300 } })
state:restore(d)
check(same(d.f, { x = 50, y = 60, w = 400, h = 300 }), "the frame from before the drag is the natural one, got " .. show(d.f))

-- Bad input fails without touching the window
r = state:place(d, { kind = "sideways", frame = half })
check(r.status == "failed", "an unknown kind fails")

-- Memory survives a restart, pruning closed windows
local k = fakeWindow(6, "com.example.k", { x = 700, y = 300, w = 900, h = 500 })
state:place(k, { kind = "maximize", position = "maximize", frame = SF, screenFrame = SF })
local dead = fakeWindow(99, "com.example.dead", { x = 0, y = 0, w = 300, h = 300 })
state:place(dead, { kind = "maximize", position = "maximize", frame = SF, screenFrame = SF })
alive[99] = nil
Core, state = boot()
check(state.memory.entries[6] ~= nil and state.memory.entries[99] == nil, "after a restart entries load and closed windows are pruned")
state:restore(k)
check(same(k.f, { x = 700, y = 300, w = 900, h = 500 }), "and a restore after the restart uses them")

print(Core.inspect())
print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
