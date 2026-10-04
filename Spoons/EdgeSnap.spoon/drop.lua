-- The drop: the placement runs through Core.window(), WindowState's place action
-- with source "snap", after the mouse up so nothing resizes the window while macOS
-- is still dragging it

local Core = require("CaddieCore")
local geometry = Core.geometry()
local windows = Core.titlebar().windows

return function(obj)
  -- The frame from before the drag goes along as previousFrame, so memory records the
  -- window's natural frame rather than wherever the drag left it
  function obj:_drop(target)
    local win = windows.windowFor(target.id, target.pid)
    if not win then return end
    local screen = target.zone.screen
    local sf = Core.rect(screen:frame())
    local maximize = target.position == "maximize"
    return Core.window():place(win, {
      kind = maximize and "maximize" or "tile", position = target.position,
      frame = maximize and sf or geometry.baseTile(target.position, sf), screenFrame = sf, screen = screen,
      previousFrame = target.start, source = "snap",
    })
  end
end
