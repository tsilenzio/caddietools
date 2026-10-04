-- Run: lua test/test_positions.lua   (from the repo root)
-- Quarters, thirds, and two thirds: geometry, repeat plans, and TileManager.
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end
local function same(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

stub.install(".")
local geometry = require("CaddieCore").geometry()
local SF = { x = 0, y = 0, w = 3000, h = 1200 }
local TALL = { x = 0, y = 0, w = 1200, h = 3000 }

-- Geometry ----------------------------------------------------------------------

check(same(geometry.baseTile("topLeft", SF), { x = 0, y = 0, w = 1500, h = 600 }), "top-left quarter")
check(same(geometry.baseTile("bottomRight", SF), { x = 1500, y = 600, w = 1500, h = 600 }), "bottom-right quarter")
check(same(geometry.baseTile("firstThird", SF), { x = 0, y = 0, w = 1000, h = 1200 }), "first third")
check(same(geometry.baseTile("centerThird", SF), { x = 1000, y = 0, w = 1000, h = 1200 }), "center third")
check(same(geometry.baseTile("lastThird", SF), { x = 2000, y = 0, w = 1000, h = 1200 }), "last third")
check(same(geometry.baseTile("firstTwoThirds", SF), { x = 0, y = 0, w = 2000, h = 1200 }), "first two thirds")
check(same(geometry.baseTile("lastTwoThirds", SF), { x = 1000, y = 0, w = 2000, h = 1200 }), "last two thirds")
check(same(geometry.baseTile("centerTwoThirds", SF), { x = 500, y = 0, w = 2000, h = 1200 }), "center two thirds")
check(same(geometry.baseTile("firstThird", TALL), { x = 0, y = 0, w = 1200, h = 1000 }), "portrait: first third is the top third")

local odd = { x = 7, y = 0, w = 1001, h = 500 }
local a, b, c = geometry.baseTile("firstThird", odd), geometry.baseTile("centerThird", odd), geometry.baseTile("lastThird", odd)
check(a.x + a.w == b.x and b.x + b.w == c.x and c.x + c.w == odd.x + odd.w, "thirds share edges with no rounding gap")

check(geometry.positionOf({ x = 1, y = 1, w = 998, h = 1198 }, SF) == "firstThird", "a bordered first third is recognized")

-- Repeat plans ------------------------------------------------------------------

local p, step = geometry.plan("topLeft", nil, nil)
check(p == "topLeft" and step == nil, "first press tiles in place")
for _, position in ipairs({ "topLeft", "bottomRight", "firstThird", "centerThird", "lastThird",
  "firstTwoThirds", "centerTwoThirds", "lastTwoThirds", "right", "up", "down" }) do
  p, step = geometry.plan(position, nil, position)
  check(p == position and step == 1, position .. ": repeat moves forward a monitor, same position")
end
p, step = geometry.plan("left", nil, "left")
check(p == "left" and step == -1, "left: repeat moves backward a monitor")
p, step = geometry.plan("firstThird", { key = "firstThird", position = "firstThird" }, nil)
check(p == "firstThird" and step == 1, "a window this Spoon placed repeats even off the base tile")
p, step = geometry.plan("firstThird", { key = "lastThird", position = "lastThird" }, "lastThird")
check(p == "firstThird" and step == nil, "a different key goes to its own position in place")

-- TileManager -------------------------------------------------------------------

local LEFT = { x = 0, y = 0, w = 3000, h = 1200 }
local RIGHT = { x = 3000, y = 0, w = 1500, h = 1000 }

local function fakeScreen(id, frame)
  return { id = function() return id end, frame = function() return frame end }
end
local function fakeWindow(id, frame)
  local w = { _frame = frame }
  function w:id() return id end
  function w:frame() return self._frame end
  function w:setFrame(r) self._frame = { x = r.x, y = r.y, w = r.w, h = r.h } end
  function w:application() return { bundleID = function() return "com.example.app" end } end
  return w
end

do
  for _, name in ipairs({ "TileManager", "CaddieCore" }) do package.loaded[name] = nil end
  stub.install(".")
  hs.screen.allScreens = function() return { fakeScreen(1, LEFT), fakeScreen(2, RIGHT) } end
  hs.screen.watcher.new = function() return { start = function(s) return s end, stop = function() end } end

  stub.loadSpoon("CaddieCore"):start().window().gap = 1
  local tiler = stub.loadSpoon("TileManager")

  local win = fakeWindow(7, { x = 100, y = 100, w = 400, h = 300 })
  local r = tiler:tile("topRight", win)
  check(r.status == "completed" and same(win._frame, { x = 1501, y = 0, w = 1499, h = 599 }), "top-right quarter with a 1 pt gap only on its inner sides")
  r = tiler:tile("topRight", win)
  check(r.status == "completed" and r.screenID == 2 and same(win._frame, { x = 3751, y = 0, w = 749, h = 499 }),
    "quarter repeat moves to the next monitor")

  win = fakeWindow(8, { x = 100, y = 100, w = 400, h = 300 })
  tiler:tile("firstThird", win)
  check(same(win._frame, { x = 0, y = 0, w = 999, h = 1200 }), "first third")
  r = tiler:tile("firstThird", win)
  check(r.screenID == 2 and same(win._frame, { x = 3000, y = 0, w = 499, h = 1000 }), "first third repeat moves to the next monitor")
  r = tiler:tile("firstThird", win)
  check(r.screenID == 1 and same(win._frame, { x = 0, y = 0, w = 999, h = 1200 }), "and wraps back")

  win = fakeWindow(9, { x = 100, y = 100, w = 400, h = 300 })
  tiler:tile("lastTwoThirds", win)
  check(same(win._frame, { x = 1001, y = 0, w = 1999, h = 1200 }), "last two thirds")
  r = tiler:tile("lastTwoThirds", win)
  check(r.screenID == 2 and same(win._frame, { x = 3501, y = 0, w = 999, h = 1000 }), "last two thirds repeat moves to the next monitor")

  win = fakeWindow(10, { x = 100, y = 100, w = 400, h = 300 })
  r = tiler:maximize(win)
  check(r.status == "completed" and r.screenID == 1 and same(win._frame, { x = 0, y = 0, w = 3000, h = 1200 }), "maximize in place fills the screen with no gap")
  r = tiler:maximize(win)
  check(r.status == "completed" and r.screenID == 2 and same(win._frame, { x = 3000, y = 0, w = 1500, h = 1000 }), "maximize repeat moves to the next monitor")
  r = tiler:maximize(win)
  check(r.screenID == 1, "and wraps back")

  win = fakeWindow(11, { x = 0, y = 0, w = 3000, h = 1200 })
  r = tiler:maximize(win)
  check(r.screenID == 2, "a window already filling its screen counts as maximized")
end

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
