-- While the cursor hovers the green button, Option is simulated so the button's hover
-- menu shows its Option variants. The flags tap tracks the real Option key, so a
-- simulated press never fights one the owner is holding.

local part = ...
local Core = require("CaddieCore")
local button = part("button")

local titleBar = Core.titlebar()
local props = hs.eventtap.event.properties
local now = hs.timer.absoluteTime

-- Tags events this Spoon posts so the flags tap can ignore them
local MARK = 0x475242

-- Bounds older than this are refreshed from a timer. A window moved by a hotkey can
-- show stale bounds for up to that long, which only delays the hover Option, never
-- a click.
local BOUNDS_TTL_NS = 0.5e9

local function postAlt(down)
  local e = hs.eventtap.event.newKeyEvent(hs.keycodes.map.alt, down)
  e:setProperty(props.eventSourceUserData, MARK)
  e:post()
end

return function(obj)
  function obj:_setHoverAlt(on)
    if on == self.hoverAlt then return end
    self.hoverAlt = on
    if not self.physicalAlt then postAlt(on) end
  end

  function obj:_releaseAlt()
    if self.hoverAlt and not self.physicalAlt then postAlt(false) end
    self.hoverAlt = false
  end

  -- Stale bounds are refreshed from a timer, never inside this tap. The tap holds
  -- every cursor move until it returns, and hs.window.list() takes 1.8 to 4 ms. The
  -- move is judged against the cached bounds now and judged again once the refresh
  -- lands, so a cursor that stops in the corner of a window that just moved still
  -- gets its hover.
  function obj:_onMouseMoved(event)
    local p = event:location()
    self.lastMovePoint = p
    if (not titleBar.bounds or now() - titleBar.boundsAt > BOUNDS_TTL_NS) and not self.boundsTimer then
      self.boundsTimer = hs.timer.doAfter(0, self.onBoundsRefresh)
    end
    self:_hoverAt(p)
    return false
  end

  function obj:_boundsRefreshed()
    self.boundsTimer = nil
    titleBar:refresh()
    if self.lastMovePoint then self:_hoverAt(self.lastMovePoint) end
  end

  -- The Accessibility hit test runs from a timer, never inside the tap callback, and
  -- at most one is pending at a time
  function obj:_hoverAt(p)
    if button.inCorner(p) then
      self.hoverPoint = p
      if not self.hoverTimer then self.hoverTimer = hs.timer.doAfter(0, self.onHoverCheck) end
    else
      self.hoverPoint = nil
      if self.hoverAlt then self:_setHoverAlt(false) end
    end
  end

  function obj:_hoverCheck()
    self.hoverTimer = nil
    local p = self.hoverPoint
    if p then self:_setHoverAlt(button.element(p) ~= nil) end
  end

  function obj:_onFlags(event)
    if event:getProperty(props.eventSourceUserData) == MARK then return false end
    self.physicalAlt = event:getFlags().alt == true
    if self.hoverAlt and not self.physicalAlt then
      hs.timer.doAfter(0, function()
        if self.hoverAlt and not self.physicalAlt then postAlt(true) end
      end)
    end
    return false
  end
end
