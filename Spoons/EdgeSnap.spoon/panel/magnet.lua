-- Moving a line along its edge: after the cursor like a magnet, and into its place
-- in a corner's L

local part = ...
local shape = part("panel/shape")

local M = {}

local EDGE_OFFSET, CORNERS = shape.EDGE_OFFSET, shape.CORNERS
local vertical, clamp = shape.vertical, shape.clamp

-- Moves a line along its edge so its panel starts at `to`, shifting every rect it
-- holds in place. Returns true if it moved.
local function moveAlong(picker, to)
  local panel, vert = picker.rect, vertical(picker.side)
  local start = vert and panel.y or panel.x
  if to == start then return false end
  local dx, dy = vert and 0 or to - start, vert and to - start or 0
  local function shift(r) r.x, r.y = r.x + dx, r.y + dy end
  shift(panel)
  shift(picker.canvasFrame)
  for _, cell in ipairs(picker.cells) do
    shift(cell.rect)
    shift(cell.labelRect)
  end
  local span = picker.arms[1].span
  span[1], span[2] = span[1] + dx + dy, span[2] + dx + dy
  return true
end

-- How far a line's end still is from where it would sit at `corner`, along its
-- edge, or nil when the corner is not on the line's edge
function M.toCorner(picker, corner)
  local spec = CORNERS[corner]
  if not spec or (spec.side ~= picker.side and spec.edge ~= picker.side) then return nil end
  local u, r = picker.usable, picker.rect
  if vertical(picker.side) then
    if spec.edge == "bottom" then return (u.y + u.h - EDGE_OFFSET) - (r.y + r.h) end
    return r.y - (u.y + EDGE_OFFSET)
  end
  if spec.side == "right" then return (u.x + u.w - EDGE_OFFSET) - (r.x + r.w) end
  return r.x - (u.x + EDGE_OFFSET)
end

-- Moves a line to where its own edge's arm sits in the L `corner`, so the L can
-- take its place without anything shifting. False when the L has no arm on that edge.
function M.alignTo(picker, corner)
  for i, arm in ipairs(corner.arms) do
    if arm.side == picker.side then
      local p = corner.panels[i]
      moveAlong(picker, vertical(picker.side) and p.y or p.x)
      return true
    end
  end
  return false
end

-- Pulls a line along its edge like a magnet once the cursor is more than `lag`
-- points past either end, so that end trails the cursor by `lag`. A cursor coming
-- back toward the panel leaves it where it is. Kept on screen. Every rect it holds
-- shifts in place, since this runs for every drag event. Returns true if it moved.
function M.magnet(picker, cursor, lag)
  local u, panel = picker.usable, picker.rect
  local vert = vertical(picker.side)
  local at, start, len = vert and cursor.y or cursor.x, vert and panel.y or panel.x, vert and panel.h or panel.w
  local to = start
  if at > start + len + lag then
    to = math.floor(at - lag - len)
  elseif at < start - lag then
    to = math.floor(at + lag)
  end
  if vert then
    to = clamp(to, u.y + EDGE_OFFSET, u.y + u.h - EDGE_OFFSET - len)
  else
    to = clamp(to, u.x + EDGE_OFFSET, u.x + u.w - EDGE_OFFSET - len)
  end
  return moveAlong(picker, to)
end

return M
