-- Finding the green button under a point. The traffic lights sit in the top-left
-- corner of the title bar, so a point outside that corner of the frontmost window
-- under the cursor never reaches the Accessibility hit test.

local Core = require("CaddieCore")

local M = {}

local titleBar = Core.titlebar()

local STRIP_H = 40
local STRIP_W = 150

-- Against Core.titlebar()'s cached bounds as they stand
function M.inCorner(p)
  local e, dx, dy = titleBar:windowAt(p)
  return e ~= nil and dx < STRIP_W and dy < STRIP_H
end

function M.element(point)
  local ok, el = pcall(hs.axuielement.systemElementAtPosition, point)
  if not ok or not el then return nil end
  if el:attributeValue("AXSubrole") ~= "AXFullScreenButton" then return nil end
  return el
end

return M
