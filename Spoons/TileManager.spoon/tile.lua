-- Planning a tile. Each plan here and in move.lua and maximize.lua returns an early
-- result when there is nothing to place, or the options for WindowState's place
-- action. The window's id and frame ride along, so place does not read them again.

local part = ...
local Core = require("CaddieCore")
local geometry = Core.geometry()
local last = part("last")

local M = {}

local rect = Core.rect

function M.early(status, reason, windowID, current)
  return { status = status, reason = reason, windowID = windowID, previousFrame = current }
end

-- The entry for an explicit destination screen, else the one holding most of the frame
function M.screenEntry(screen, entries, current)
  local id = screen and screen:id()
  for _, e in ipairs(entries) do
    if e.id == id then return e end
  end
  return geometry.screenFor(current, entries)
end

-- Compared against the untransformed base tile, never the frame the rules produce,
-- since the plan is made before they run
function M.plan(key, win, opts)
  if not geometry.POSITIONS[key] then return M.early("failed", "unknown position " .. tostring(key)) end
  if not win then return M.early("unchanged", "no window") end
  local id, current = win:id(), rect(win:frame())
  local entries = geometry.describeScreens(Core.screens())
  if #entries == 0 then return M.early("unchanged", "no screens", id, current) end
  local here = M.screenEntry(opts.screen, entries, current)
  local position, step = geometry.plan(key, last.lastFor(id, current), geometry.positionOf(current, here.frame))
  local dest = here
  -- A named screen never cycles on as a repeated hotkey does
  if step and not opts.screen then
    dest = geometry.nextScreen(entries, here, step)
    if dest == here then return M.early("unchanged", "single screen", id, current) end
  end
  return nil, {
    kind = "tile", position = position, frame = geometry.baseTile(position, dest.frame),
    screenFrame = dest.frame, screen = dest.screen, movedScreen = dest ~= here,
    windowID = id, currentFrame = current, previousFrame = opts.previousFrame, source = opts.source or "tile",
  }
end

return M
