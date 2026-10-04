-- Which cell the cursor selects. Across the edge the whole strip from the screen
-- edge to a panel's far side counts, since the cursor reaches the edge faster than
-- a panel appears and stops beside it rather than in it. Along the edge a cell
-- counts only within the panel's own length.

local part = ...
local shape = part("panel/shape")

local M = {}

local GAP = shape.GAP
local vertical, inside = shape.vertical, shape.inside

-- True while p is in a line's strip, the forgiving band across its edge
function M.inStrip(picker, p)
  return inside(picker.arms[1].strip, p)
end

-- The arm of an L whose strip holds p, or nil. Past the corner only one strip can.
function M.armAt(corner, p)
  for _, arm in ipairs(corner.arms) do
    if inside(arm.strip, p) then return arm end
  end
  return nil
end

-- Along one arm, within its span: the middle cell's band, its gaps included, or the
-- end cell on either side up to the span's end. Nil outside the span.
local function along(picker, arm, p)
  local idx, at = arm.cells, vertical(arm.side) and p.y or p.x
  if at < arm.span[1] or at >= arm.span[2] then return nil end
  local mid = picker.cells[idx[2]].rect
  local lo, hi = vertical(arm.side) and mid.y or mid.x, vertical(arm.side) and mid.y + mid.h or mid.x + mid.w
  if at < lo - GAP / 2 then return idx[1] end
  if at >= hi + GAP / 2 then return idx[3] end
  return idx[2]
end

-- The index of the cell selected at p, or nil off every strip or past every span.
-- Where an L's two strips cross, at the corner, the shared cell is selected.
function M.hit(picker, p)
  local found = nil
  for _, arm in ipairs(picker.arms) do
    if inside(arm.strip, p) then
      if found then return picker.shared end
      found = arm
    end
  end
  return found and along(picker, found, p) or nil
end

return M
