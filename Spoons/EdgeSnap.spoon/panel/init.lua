-- The quick select panel shown while a window is held at a screen edge, after
-- BetterTouchTool's. Along an edge, a line of three cells: one corner, the edge's own
-- placement, and the other corner. A column at the left and right edges, a row at
-- the top and bottom. In a corner, an L joining the two edges' lines, sharing the
-- corner cell, so a drag can pass from one edge's choices to the other's.
--
-- Layout and selection are plain arithmetic, so the drag tap can call them. This
-- file gathers the parts into one table.

local part = ...

local M = {}

for _, name in ipairs({ "panel/layout", "panel/select", "panel/magnet", "panel/render" }) do
  for k, v in pairs(part(name)) do M[k] = v end
end

return M
