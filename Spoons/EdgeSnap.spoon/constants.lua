-- Distances and mappings shared by the drag's parts

local M = {}

-- A window that moved less than this since the mouse down is not being dragged,
-- which rules out text selection and a tab torn out of a Chrome window
M.MOVED_MIN = 3
-- A window dragged up against the menu bar stops there while the cursor stays as
-- far below as it was grabbed, up to the 40 pt title band. Within this many points
-- of that spot the window counts as pinned against the top.
M.PIN_SLACK = 3
M.PREVIEW_INSET = 6
-- The edge each placement belongs to, for the panels. Corners have no panel.
M.PICKER_SIDES = { left = "left", right = "right", maximize = "top", down = "bottom" }
-- A corner zone opens the L joining its two edges' panels
M.PICKER_CORNERS = { topLeft = true, topRight = true, bottomLeft = true, bottomRight = true }
M.PREVIEW_RADIUS = 10

return M
