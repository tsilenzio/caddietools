-- Run: lua test/test_tilemanager.lua   (from the repo root)
-- TileManager through the real WindowState, its rules set the way the profile does.
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end

local function sameRect(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local function fmt(r)
  if not r then return "nil" end
  return string.format("{%s,%s,%s,%s}", r.x, r.y, r.w, r.h)
end

-- Fake screens and windows ------------------------------------------------------

local function fakeScreen(id, frame)
  return {
    frame = function() return { x = frame.x, y = frame.y, w = frame.w, h = frame.h } end,
    id = function() return id end,
  }
end

local function fakeWindow(id, bundle, frame)
  local w = { _frame = frame, sets = 0 }
  function w:id() return id end
  function w:frame() local f = self._frame return { x = f.x, y = f.y, w = f.w, h = f.h } end
  function w:setFrame(r, duration)
    self._frame = { x = r.x, y = r.y, w = r.w, h = r.h }
    self.duration = duration
    self.sets = self.sets + 1
  end
  function w:application() return { bundleID = function() return bundle end } end
  return w
end

-- Usable frames, menu bar and Dock already excluded. Listed out of order on
-- purpose, with Built-in first the way hs.screen.allScreens() puts the main screen.
local BUILTIN = { x = 0, y = 33, w = 1512, h = 949 }
local E1 = { x = -1920, y = 25, w = 1920, h = 1055 }
local E2 = { x = 1512, y = 25, w = 2560, h = 1415 }
local ROW = { fakeScreen(1, BUILTIN), fakeScreen(2, E1), fakeScreen(3, E2) }

local TOP = { x = 0, y = -1055, w = 1920, h = 1055 }
local STACK = { fakeScreen(1, BUILTIN), fakeScreen(4, TOP) }

local function rightHalf(f)
  local half = math.floor(f.w / 2)
  return { x = f.x + half, y = f.y, w = f.w - half, h = f.h }
end

local function topHalf(f)
  return { x = f.x, y = f.y, w = f.w, h = math.floor(f.h / 2) }
end

-- A right half's gap is on its left side only, the other three being on the screen edge
local function gapped(f, g)
  return { x = f.x + g, y = f.y, w = f.w - g, h = f.h }
end

-- Setup -----------------------------------------------------------------------

local screens = ROW
local bound = {}

local function install()
  for _, name in ipairs({ "TileManager", "CaddieCore" }) do package.loaded[name] = nil end
  stub.install(".")
  hs.screen.allScreens = function() return screens end
  hs.hotkey.bind = function(mods, key, pressed)
    bound[key] = pressed
    return { delete = function() bound[key] = nil end }
  end
end

local function suite()
  install()
  local invalidateScreens
  -- TileManager caches screens behind a screen watcher, so the test fires it on layout changes
  hs.screen.watcher.new = function(fn)
    invalidateScreens = fn
    return { start = function(self) return self end, stop = function() end }
  end
  local Core = stub.loadSpoon("CaddieCore")
  Core:start()
  check(type(Core.scope) == "function", "Core:start() leaves the Core.scope constructor in place")
  local state = Core.window()
  state.minSize = { w = 400, h = 300 }
  state.centerSmall = { fraction = 0.8, apps = { ["com.apple.calculator"] = true } }
  local tiler = stub.loadSpoon("TileManager")
  local metrics = Core.metrics
  metrics.reset()

  local function useScreens(list)
    screens = list
    if invalidateScreens then invalidateScreens() end
  end

  local nextID = 100
  local function newWindow(bundle, frame)
    nextID = nextID + 1
    return fakeWindow(nextID, bundle or "com.example.app", frame or { x = 100, y = 100, w = 600, h = 400 })
  end

  -- Wrap-around across E1, Built-in, E2, from an untiled window on Built-in
  useScreens(ROW)
  local win = newWindow()
  local r = tiler:tile("right", win)
  check(r.status == "completed" and sameRect(r.finalFrame, rightHalf(BUILTIN)) and r.screenID == 1
    and r.movedScreen == false and win.duration == 0, "first press tiles on the current screen")
  check(r.windowID == win:id() and r.app == "com.example.app" and sameRect(r.previousFrame, { x = 100, y = 100, w = 600, h = 400 }),
    "result carries window fields")
  r = tiler:tile("right", win)
  check(r.status == "completed" and r.screenID == 3 and r.movedScreen == true and sameRect(win._frame, rightHalf(E2)),
    "repeat press moves to the next screen, same tile")
  r = tiler:tile("right", win)
  check(r.screenID == 2 and sameRect(win._frame, rightHalf(E1)), "third press wraps to E1, got " .. fmt(win._frame))
  r = tiler:tile("right", win)
  check(r.screenID == 1 and sameRect(win._frame, rightHalf(BUILTIN)), "fourth press returns to Built-in")

  -- Left mirrors, and switching direction stays on the screen first
  r = tiler:tile("left", win)
  check(r.screenID == 1 and r.movedScreen == false, "other direction retiles on the same screen")
  r = tiler:tile("left", win)
  check(r.screenID == 2 and r.movedScreen == true, "left repeat moves to E1")
  r = tiler:tile("left", win)
  check(r.screenID == 3, "left wraps from E1 to E2")

  -- 15 pt off the tile (size increments) still counts as tiled
  win._frame = rightHalf(BUILTIN)
  win._frame.w = win._frame.w - 15
  r = tiler:tile("right", win)
  check(r.screenID == 3, "20 pt slack counts a near-miss as tiled")

  -- Up and down on a single row
  win = newWindow()
  r = tiler:tile("up", win)
  check(r.status == "completed" and sameRect(win._frame, topHalf(BUILTIN)), "up tiles the top half")
  r = tiler:tile("up", win)
  check(r.status == "completed" and r.screenID == 3 and sameRect(win._frame, topHalf(E2)),
    "up repeat on a single row moves forward in reading order")

  -- Up and down with a second row
  useScreens(STACK)
  win = newWindow()
  tiler:tile("up", win)
  r = tiler:tile("up", win)
  check(r.status == "completed" and r.screenID == 4 and sameRect(win._frame, topHalf(TOP)), "up repeat moves to the upper row")
  useScreens(ROW)

  -- The gap moves the inner edge by 8, the repeat check still sees the base tile
  state.gap = 8
  win = newWindow()
  r = tiler:tile("right", win)
  check(sameRect(r.finalFrame, gapped(rightHalf(BUILTIN), 8)), "the gap shapes the tile, got " .. fmt(r.finalFrame))
  r = tiler:tile("right", win)
  check(r.screenID == 3 and sameRect(win._frame, gapped(rightHalf(E2), 8)), "the gap does not break repeat detection")

  -- A gap past the slack still repeats through the remembered applied frame
  state.gap = 30
  win = newWindow()
  tiler:tile("right", win)
  r = tiler:tile("right", win)
  check(r.screenID == 3, "large gap repeats through the last applied frame")

  -- Center-small moves edges about 75 pt, same mechanism
  state.gap = 8
  win = newWindow("com.apple.calculator")
  tiler:tile("right", win)
  r = tiler:tile("right", win)
  check(r.screenID == 3 and r.movedScreen, "centersmall tile repeats to the next screen")

  -- Exclusion veto
  state.excluded = { ["com.apple.systempreferences"] = true }
  win = newWindow("com.apple.systempreferences")
  r = tiler:tile("left", win)
  check(r.status == "vetoed" and r.by == "WindowState" and r.reason == "excluded app com.apple.systempreferences"
    and win.sets == 0, "an excluded app is vetoed")
  check(r.windowID == win:id() and r.app == "com.apple.systempreferences", "vetoed result carries window fields")

  -- Minimum size veto, checked after the gap shaped the frame
  state.gap = 200
  win = newWindow()
  r = tiler:tile("up", win)
  check(r.status == "vetoed" and r.by == "WindowState" and r.reason:find("below minimum", 1, true) and win.sets == 0,
    "the minimum size vetoes the shaped frame")
  state.gap = 0

  -- Every tile and maximize runs WindowState's place chain in rule order
  check(state:stack("place"):find("1. WindowState.exclude  guard\n.*2. WindowState.preset.*3. WindowState.center"
    .. ".*4. WindowState.gap.*5. WindowState.minimum"), "place chain in rule order")
  win = newWindow()
  tiler:tile("left", win)
  r = tiler:maximize(win)
  check(r.status == "completed" and sameRect(r.finalFrame, BUILTIN) and r.screenID == 1, "maximize fills the screen")

  -- Focused window fallback, no window, and undo through the hotkey
  hs.window.focusedWindow = function() return nil end
  r = tiler:tile("left")
  check(r.status == "unchanged" and r.reason == "no window", "no window is unchanged")
  hs.window.focusedWindow = function() return win end
  tiler:bindHotkeys({ left = { {}, "left" }, undo = { {}, "z" } })
  check(bound.left == nil, "bindHotkeys before start binds nothing")
  tiler:start()
  local before = win:frame()
  bound.left()
  check(not sameRect(win._frame, before), "left hotkey tiles the focused window")
  bound.z()
  check(sameRect(win._frame, before), "undo hotkey restores the previous frame")
  tiler:stop()
  check(bound.left == nil and bound.z == nil, "stop releases hotkeys")

  local snap = metrics.snapshot()
  check(snap["WindowState.place"] and snap["WindowState.place"].count > 0
    and snap["WindowState.undo"] and snap["WindowState.undo"].count == 1, "metrics recorded under WindowState's action names")

  print(Core.inspect())
end

suite()

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
