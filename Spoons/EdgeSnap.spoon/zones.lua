-- Which edge or corner of which screen a point is at, measured from each screen's
-- usable frame, with shared edges between screens counted as seams

local part = ...
local PIN_SLACK = part("constants").PIN_SLACK

local function inside(f, x, y)
  return x >= f.x and y >= f.y and x < f.x + f.w and y < f.y + f.h
end

return function(obj)
  -- True when the point just past an edge lies on another screen, so the edge is a
  -- seam the cursor crosses rather than one it stops at
  function obj:_seam(s, x, y)
    for _, other in ipairs(self.dragScreens) do
      if other ~= s and inside(other.full, x, y) then return true end
    end
    return false
  end

  -- The screen and placement for a cursor at p, or nil away from every edge. Edges
  -- are measured from the usable frame, so the top edge sits under the menu bar
  -- whatever its height on that screen, notched or not, and the bottom edge sits
  -- above a visible Dock. Seams are found on the physical frames, only for an edge
  -- the cursor is near. Returns values rather than a table, since it runs for every
  -- drag event: the screen, the placement, and whether a seam is involved.
  --
  -- `pin` is how far below the window's top the cursor holds it, plus PIN_SLACK. A
  -- cursor within that of the top of the usable frame has the window pinned against
  -- the menu bar, which counts as the top edge without pushing the cursor up through
  -- the title bar, where macOS can open Mission Control first. Only a top edge with
  -- no screen above it, since a window can carry on on to a screen above.
  function obj:_zoneAt(p, pin)
    for _, s in ipairs(self.dragScreens or {}) do
      local f = s.full
      if inside(f, p.x, p.y) then
        local u, z, seams = s.frame, self.edgeZone, self.seams
        local right, bottom = u.x + u.w, u.y + u.h
        local nearL, nearR = p.x < u.x + z, p.x >= right - z
        local nearT, nearB = p.y < u.y + z, p.y >= bottom - z
        local pinned = not nearT and pin ~= nil and p.y >= u.y and p.y < u.y + pin
        nearT = nearT or pinned
        if not (nearL or nearR or nearT or nearB) then return nil end
        local seamL = nearL and self:_seam(s, f.x - 1, p.y)
        local seamR = nearR and self:_seam(s, f.x + f.w, p.y)
        local seamT = nearT and self:_seam(s, p.x, f.y - 1)
        local seamB = nearB and self:_seam(s, p.x, f.y + f.h)
        local onLeft = nearL and (seams or not seamL)
        local onRight = nearR and (seams or not seamR)
        local onTop = nearT and not (pinned and seamT) and (seams or not seamT)
        local onBottom = nearB and (seams or not seamB)
        if not (onLeft or onRight or onTop or onBottom) then return nil end
        local seam = (onLeft and seamL) or (onRight and seamR) or (onTop and seamT) or (onBottom and seamB)
        -- The same reach from every corner of every screen, capped so a short edge's
        -- two corners never overlap
        local cw, ch = math.min(self.cornerZone, u.w / 2), math.min(self.cornerZone, u.h / 2)
        local nearSide = p.x - u.x < cw or right - p.x <= cw
        local nearEnd = p.y - u.y < ch or bottom - p.y <= ch
        if ((onLeft or onRight) and nearEnd) or ((onTop or onBottom) and nearSide) then
          local upper, leftHalf = p.y - u.y < u.h / 2, p.x - u.x < u.w / 2
          if upper then return s, leftHalf and "topLeft" or "topRight", seam end
          return s, leftHalf and "bottomLeft" or "bottomRight", seam
        end
        if onLeft then return s, "left", seam end
        if onRight then return s, "right", seam end
        if onTop then return s, "maximize", seam end
        return s, "down", seam
      end
    end
    return nil
  end
end
