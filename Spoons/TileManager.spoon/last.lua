-- What this Spoon last did per window: the key pressed, the position it produced, and
-- the frame applied after WindowState's rules. Needed because the base tile comparison
-- only tolerates rules that move each edge by 20 pt or less, and center-small shrinks
-- a tile far more. Move uses the key to keep repeats working on the new screen.

local Core = require("CaddieCore")
local geometry = Core.geometry()

local M = {}

local lastTile = {}

-- The record for a window that still sits where this Spoon put it. A window placed
-- by something else, such as an edge drop, falls back to WindowState's memory.
function M.lastFor(windowID, current)
  local last = lastTile[windowID]
  if last and geometry.near(current, last.frame) then return last end
  local e = Core.window():trusted(windowID, current)
  local kind = e and e.applied.kind
  if kind and (geometry.POSITIONS[kind] or kind == "maximize") then return { key = kind, position = kind } end
  return nil
end

function M.remember(result, key, position)
  if result.status ~= "completed" then return end
  if position then
    lastTile[result.windowID] = { key = key or position, position = position, frame = Core.rect(result.finalFrame) }
  else
    lastTile[result.windowID] = nil
  end
end

function M.reset()
  lastTile = {}
end

return M
