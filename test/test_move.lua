-- Run: lua test/test_move.lua   (from the repo root)
-- Covers geometry.remap, the Space chord, and TileManager:moveScreen.
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end

local function same(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- A layout like the owner's: the laptop below, an ultrawide above and to the left
local LAPTOP = { x = 0, y = 40, w = 2056, h = 1250 }
local WIDE = { x = -2412, y = -1410, w = 3440, h = 1410 }

local function fakeScreen(id, frame)
  return { id = function() return id end, frame = function() return frame end }
end

local function fakeWindow(id, bundle, frame)
  local w = { _id = id, _frame = frame, sets = 0 }
  function w:id() return self._id end
  function w:frame() return self._frame end
  function w:setFrame(r) self._frame = { x = r.x, y = r.y, w = r.w, h = r.h } self.sets = self.sets + 1 end
  function w:application() return { bundleID = function() return bundle end } end
  return w
end

local function freshModules()
  for _, name in ipairs({ "TileManager", "CaddieCore" }) do
    package.loaded[name] = nil
  end
end

-- remap -------------------------------------------------------------------------

freshModules()
stub.install(".")
local geometry = require("CaddieCore").geometry()

local bottomHalf = { x = 1, y = 40 + 625 + 1, w = 2056 - 2, h = 625 - 2 }
check(same(geometry.remap(bottomHalf, LAPTOP, WIDE, 1),
  { x = -2412 + 1, y = -1410 + 705 + 1, w = 3440 - 2, h = 705 - 2 }),
  "remap: a bordered bottom half becomes the full-width bottom half, border kept at 1")

local rightHalf = { x = 1028 + 1, y = 40 + 1, w = 1028 - 2, h = 1250 - 2 }
check(same(geometry.remap(rightHalf, LAPTOP, WIDE, 1),
  { x = -2412 + 1720 + 1, y = -1410 + 1, w = 1720 - 2, h = 1410 - 2 }),
  "remap: a bordered right half stays the right half")

local maximized = { x = 1, y = 41, w = 2054, h = 1248 }
check(same(geometry.remap(maximized, LAPTOP, WIDE, 1),
  { x = -2411, y = -1409, w = 3438, h = 1408 }),
  "remap: maximized stays maximized")

local leftHalf = { x = 0, y = 40, w = 1028 - 1, h = 1250 }
check(same(geometry.remap(leftHalf, LAPTOP, WIDE, { right = 1 }),
  { x = -2412, y = -1410, w = 1720 - 1, h = 1410 }),
  "remap: a left half with a gap only on its right keeps it there, flush sides stay flush")

local loose = { x = 514, y = 352.5, w = 1028, h = 625 }
check(same(geometry.remap(loose, LAPTOP, WIDE, 0),
  { x = -2412 + 860, y = -1410 + 353, w = 1720, h = 705 }),
  "remap: a hand-sized window keeps its fractions with no border added")

-- Space chord -------------------------------------------------------------------

local chord = dofile("Spoons/TileManager.spoon/chord.lua")
local function key(code, kind, flags)
  return {
    getKeyCode = function() return code end,
    getType = function() return kind end,
    getFlags = function() return flags or {} end,
  }
end
local HYPER = { ctrl = true, alt = true, cmd = true }

check(chord.handle(key(49, "keyDown", HYPER)) == true and chord.held, "chord: Space with the chord is swallowed and held")
check(chord.handle(key(49, "keyDown", {})) == true, "chord: key repeat while held is swallowed")
check(chord.handle(key(123, "keyDown", HYPER)) == false, "chord: arrows pass through to the hotkeys")
check(chord.handle(key(49, "keyUp", {})) == true and not chord.held, "chord: the release is swallowed and clears the hold")
check(chord.handle(key(49, "keyDown", { cmd = true })) == false and not chord.held, "chord: Space without the full chord passes")
check(chord.handle(key(49, "keyUp", {})) == false, "chord: an unrelated Space release passes")

-- moveScreen --------------------------------------------------------------------

do
  freshModules()
  stub.install(".")
  local screens = { fakeScreen(1, LAPTOP), fakeScreen(2, WIDE) }
  hs.screen.allScreens = function() return screens end
  -- Screen caches clear through the watcher, so the test fires it on layout changes
  local onScreensChanged = {}
  hs.screen.watcher.new = function(fn)
    table.insert(onScreensChanged, fn)
    return { start = function(s) return s end, stop = function() end }
  end
  local function setScreens(list)
    screens = list
    for _, fn in ipairs(onScreensChanged) do fn() end
  end
  local hotkeys = {}
  hs.hotkey.bind = function(mods, k, fn) hotkeys[k] = fn return { delete = function() end } end

  local state = stub.loadSpoon("CaddieCore"):start().window()
  state.gap = 1
  local tiler = stub.loadSpoon("TileManager")

  local win = fakeWindow(10, "com.apple.TextEdit", { x = 300, y = 300, w = 800, h = 600 })
  tiler:tile("down", win)
  local r = tiler:moveScreen("right", win)
  check(r.status == "completed" and r.movedScreen and r.screenID == 2
    and same(win._frame, { x = -2412, y = -704, w = 3440, h = 704 }),
    "bottom half on the laptop moves to the full-width bottom half of the wide screen")

  local rt = tiler:tile("down", win)
  check(rt.status == "completed" and rt.screenID == 1, "repeat-to-move still works for the moved tile")

  win._frame = { x = 300, y = 300, w = 800, h = 600 }
  r = tiler:moveScreen("left", win)
  check(r.status == "completed" and same(win._frame, { x = -2412 + 502, y = -1410 + 293, w = 1339, h = 677 }),
    "a hand-sized window scales by its fractions")

  check(state.undoStack:depth(10) >= 3, "moves are recorded for undo")

  setScreens({ fakeScreen(1, LAPTOP) })
  local sets = win.sets
  r = tiler:moveScreen("right", win)
  check(r.status == "unchanged" and win.sets == sets, "one screen leaves the window alone")
  setScreens({ fakeScreen(1, LAPTOP), fakeScreen(2, WIDE) })

  state.excluded = { ["com.apple.TextEdit"] = true }
  r = tiler:moveScreen("right", win)
  check(r.status == "vetoed" and r.by == "WindowState" and win.sets == sets, "excluded apps are vetoed")
  state.excluded = nil

  -- The arrow hotkey routes through the chord state
  tiler:bindHotkeys({ right = { { "ctrl", "alt", "cmd" }, "right" } })
  tiler:start()
  local chordState = tiler.chord
  win._frame = { x = 300, y = 300, w = 800, h = 600 }
  hs.window.focusedWindow = function() return win end
  chordState.held = true
  hotkeys.right()
  check(win._frame.y < 0, "arrow with Space held moves to the other screen")
  chordState.held = false
  win._frame = { x = 300, y = 300, w = 800, h = 600 }
  hotkeys.right()
  check(win._frame.y > 0 and win._frame.x > 1000, "arrow without Space tiles on the same screen")
  tiler:bindHotkeys({ right = { { "ctrl", "alt", "cmd" }, "right" } })
  local held = table.concat(tiler.scope:list(), ",")
  check(held:find("space chord tap", 1, true) and hotkeys.right, "rebinding while started keeps the chord tap and the hotkeys")
  tiler:stop()
  check(chordState.held == false, "stop clears the chord state")
end

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
