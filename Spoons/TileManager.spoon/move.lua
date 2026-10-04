-- Planning a move to the next screen in the pressed direction, same layout. Tiled
-- and maximized windows keep their gap border, and a hand-sized window scales by the
-- same fractions. The frame already carries the border, so WindowState's gap rule
-- leaves moves alone.

local part = ...
local Core = require("CaddieCore")
local geometry = Core.geometry()
local last = part("last")
local early = part("tile").early

local M = {}

local DIRECTIONS = { left = true, right = true, up = true, down = true }

-- Reading order across monitors: left steps backward, every other direction forward,
-- wrapping. Returns `here` when it is the only monitor.
local function nextScreen(entries, here, direction)
  return geometry.nextScreen(entries, here, direction == "left" and -1 or 1)
end

-- The tile position the window sits in, if any. A window tiled before a reload has no
-- record, so the geometry is checked as well.
local function positionNow(windowID, current, here)
  local l = last.lastFor(windowID, current)
  if l then return l.position, l.key end
  return geometry.positionOf(current, here.frame), nil
end

-- The border a placed window carries inside its tile or screen, read side by side
-- from the window itself so it is right whatever gap, if any, was applied. Sides
-- flush with the screen carry none, so the four can differ.
local function borderOf(current, ref)
  local function side(b)
    if b < 0 or b > geometry.SLACK then return 0 end
    return b
  end
  return {
    left = side(current.x - ref.x),
    top = side(current.y - ref.y),
    right = side(ref.x + ref.w - current.x - current.w),
    bottom = side(ref.y + ref.h - current.y - current.h),
  }
end

-- Returns the early result or the place options, plus the key that last placed the
-- tile so repeats keep working on the new screen
function M.plan(direction, win)
  if not DIRECTIONS[direction] then return early("failed", "unknown direction " .. tostring(direction)) end
  if not win then return early("unchanged", "no window") end
  local id, current = win:id(), Core.rect(win:frame())
  local entries = geometry.describeScreens(Core.screens())
  if #entries == 0 then return early("unchanged", "no screens", id, current) end
  local here = geometry.screenFor(current, entries)
  local dest = nextScreen(entries, here, direction)
  if dest == here then return early("unchanged", "single screen", id, current) end

  local tilePosition, lastKey = positionNow(id, current, here)
  local border = 0
  if tilePosition then
    border = borderOf(current, geometry.baseTile(tilePosition, here.frame))
  elseif geometry.near(current, here.frame) then
    border = borderOf(current, here.frame)
  end
  return nil, {
    kind = "move", position = tilePosition, frame = geometry.remap(current, here.frame, dest.frame, border),
    screenFrame = dest.frame, screen = dest.screen, movedScreen = true,
    windowID = id, currentFrame = current, source = "tile",
  }, lastKey
end

return M
