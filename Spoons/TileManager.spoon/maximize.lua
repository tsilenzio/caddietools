-- Planning a maximize. A window already maximized, by this Spoon or by geometry,
-- moves to the next monitor, maximized.

local part = ...
local Core = require("CaddieCore")
local geometry = Core.geometry()
local last = part("last")
local tile = part("tile")

local M = {}

function M.plan(win, opts)
  if not win then return tile.early("unchanged", "no window") end
  local id, current = win:id(), Core.rect(win:frame())
  local entries = geometry.describeScreens(Core.screens())
  if #entries == 0 then return tile.early("unchanged", "no screens", id, current) end
  local here = tile.screenEntry(opts.screen, entries, current)
  local l = last.lastFor(id, current)
  local dest = here
  if not opts.screen and ((l and l.position == "maximize") or geometry.near(current, here.frame)) then
    dest = geometry.nextScreen(entries, here, 1)
    if dest == here then return tile.early("unchanged", "single screen", id, current) end
  end
  return nil, {
    kind = "maximize", position = "maximize", frame = Core.rect(dest.frame),
    screenFrame = dest.frame, screen = dest.screen, movedScreen = dest ~= here,
    windowID = id, currentFrame = current, previousFrame = opts.previousFrame, source = opts.source or "tile",
  }
end

return M
