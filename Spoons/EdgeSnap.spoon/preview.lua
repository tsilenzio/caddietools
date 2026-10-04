-- The preview: a rounded translucent rectangle showing where a drop would put the
-- window, grown out of the point where the cursor reached the edge

local part = ...
local geometry = require("CaddieCore").geometry()
local constants = part("constants")
local PREVIEW_INSET, PREVIEW_RADIUS = constants.PREVIEW_INSET, constants.PREVIEW_RADIUS

return function(obj)
  -- Grows from the point where the cursor reached the edge, as Rectangle's footprint
  -- does. Moving to another screen's edge while shown glides from where it is.
  function obj:_showPreview(screenFrame, position, from, extra)
    local f = position == "maximize" and screenFrame or geometry.baseTile(position, screenFrame)
    local target = {
      x = f.x + PREVIEW_INSET, y = f.y + PREVIEW_INSET,
      w = f.w - 2 * PREVIEW_INSET, h = f.h - 2 * PREVIEW_INSET,
    }
    local c = self.preview
    local start = nil
    if not self.previewShown then
      local p = from or { x = target.x + target.w / 2, y = target.y + target.h }
      start = {
        x = math.max(target.x, math.min(target.x + target.w - 1, p.x)),
        y = math.max(target.y, math.min(target.y + target.h - 1, p.y)), w = 1, h = 1,
      }
      c:alpha(0)
      c:frame(start)
      c:show()
      self.previewShown = true
    end
    self:_animate({ canvas = c, fromFrame = start, frame = target, alpha = 1,
      grow = self.previewGrow + (extra or 0), fade = self.previewFadeIn + (extra or 0) })
  end

  function obj:_hidePreview()
    if not self.preview or not self.previewShown then return end
    self.previewShown = false
    self:_animate({ canvas = self.preview, alpha = 0, grow = 0, fade = self.previewFadeOut, done = function()
      if self.preview and not self.previewShown then self.preview:hide() end
    end })
  end

  function obj:_newPreview()
    local c = hs.canvas.new({ x = 0, y = 0, w = 1, h = 1 })
    c:level(hs.canvas.windowLevels.overlay)
    c:behavior({ "canJoinAllSpaces", "transient" })
    c:appendElements({
      type = "rectangle", action = "strokeAndFill",
      roundedRectRadii = { xRadius = PREVIEW_RADIUS, yRadius = PREVIEW_RADIUS },
      fillColor = { white = 1, alpha = 0.2 },
      strokeColor = { white = 1, alpha = 0.5 }, strokeWidth = 1,
    })
    return c
  end
end
