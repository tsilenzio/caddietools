-- Rectangle's Mission Control guard. Dragging a window into the top of the screen
-- and pushing on can open Mission Control, so a sudden jump up there is held back.

local props = hs.eventtap.event.properties

return function(obj)
  -- The top of the screen whose top edge p is pinned against, when nothing is above it
  function obj:_openTop(p)
    for _, s in ipairs(self.dragScreens or {}) do
      local f = s.full
      if p.x >= f.x and p.x < f.x + f.w and p.y == f.y then
        return not self:_seam(s, p.x, f.y - 1) and f.y or nil
      end
    end
    return nil
  end

  -- Moves a drag event held at the top of a screen 1 pt down when it jerks upward, or
  -- while the guard window from the last jerk is open. Returns the point to use.
  function obj:_guardTop(event, p)
    local top = self:_openTop(p)
    local prev = self.dragPrevY
    if top and prev == top then
      local now = hs.timer.absoluteTime()
      if event:getProperty(props.mouseEventDeltaY) < -self.guardDistance then
        self.guardUntil = now + self.guardSeconds * 1e9
        p = { x = p.x, y = top + 1 }
      elseif self.guardUntil and now < self.guardUntil then
        p = { x = p.x, y = top + 1 }
      end
      if p.y ~= top then event:location(p) end
    end
    self.dragPrevY = p.y
    return p
  end
end
