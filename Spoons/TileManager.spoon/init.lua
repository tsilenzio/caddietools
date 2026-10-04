--- === TileManager ===
---
--- Rectangle Pro style tiling on Ctrl+Opt+Cmd with monitor cycling (TKT-002):
--- halves, quarters, thirds, and two thirds. Pressing a tile the window is already
--- in moves it to the next monitor in that tile, and Space held in the chord turns
--- an arrow into a move to the next monitor keeping the layout.
---
--- Every placement and the undo hotkey go through Core.window(), so WindowState's
--- memory, undo, and rules apply, and anything hooked on its actions sees them with
--- source "tile". Geometry and monitor order come from Core.geometry().

local Core = require("CaddieCore")
local part = Core.part
local last = part("last")
local tile = part("tile")
local move = part("move")
local maximize = part("maximize")

local obj = {}
obj.__index = obj

obj.name = "TileManager"
obj.version = "0.1.0"

-- The Space chord's state, read by the arrow hotkeys
obj.chord = part("chord")

local HYPER = { "ctrl", "alt", "cmd" }

-- Rectangle's layout on Ctrl+Opt+Cmd, for bindHotkeys or CaddieTools' use(). U I and
-- J K mirror the corners, D F G are the thirds, E R T the two thirds.
obj.defaultHotkeys = {
  left = { HYPER, "left" }, right = { HYPER, "right" },
  up = { HYPER, "up" }, down = { HYPER, "down" },
  maximize = { HYPER, "return" }, undo = { HYPER, "z" },
  topLeft = { HYPER, "u" }, topRight = { HYPER, "i" },
  bottomLeft = { HYPER, "j" }, bottomRight = { HYPER, "k" },
  firstThird = { HYPER, "d" }, centerThird = { HYPER, "f" }, lastThird = { HYPER, "g" },
  firstTwoThirds = { HYPER, "e" }, centerTwoThirds = { HYPER, "r" }, lastTwoThirds = { HYPER, "t" },
}

part("hotkeys")(obj)

local function placed(win, request, key)
  local result = Core.window():place(win, request)
  last.remember(result, key, request.position)
  return result
end

function obj:init()
  Core.component(self)
  return self
end

-- opts.screen places the tile on that screen instead of the window's own, without
-- cycling, and opts.previousFrame is reported as the frame before it. Maximize takes
-- the same.
function obj:tile(position, win, opts)
  opts = opts or {}
  win = win or hs.window.focusedWindow()
  local stop, request = tile.plan(position, win, opts)
  if stop then return stop end
  return placed(win, request, position)
end

function obj:moveScreen(direction, win)
  win = win or hs.window.focusedWindow()
  local stop, request, lastKey = move.plan(direction, win)
  if stop then return stop end
  return placed(win, request, lastKey)
end

function obj:maximize(win, opts)
  opts = opts or {}
  win = win or hs.window.focusedWindow()
  local stop, request = maximize.plan(win, opts)
  if stop then return stop end
  return placed(win, request, "maximize")
end

function obj:start()
  if self.scope then return self end
  self.scope = Core.scope(self.name)
  self:_rebind()
  self.scope:add(function() self:_unbind() end, "hotkeys")
  local types = hs.eventtap.event.types
  self.scope:eventtap({ types.keyDown, types.keyUp }, self.chord.handle, "space chord tap")
  self.scope:add(self.chord.reset, "space chord state")
  return self
end

function obj:stop()
  if self.scope then self.scope:close() end
  self.scope = nil
  last.reset()
  return self
end

return obj
