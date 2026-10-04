--- === TitleBarTweaks ===
---
--- Swaps the green window button (TKT-001, TKT-036). A plain click maximizes the
--- window, or restores it when it is already maximized. Double-clicking a title bar
--- does the same (TKT-037). Option-click enters real full screen. While the cursor
--- hovers the button, Option is simulated so the hover menu shows its Option
--- variants. Intended behavior: docs/window-memory.md.
---
--- The maximize and restore go through Core.window() with source "titlebar".
--- Clicks come through Core.titlebar()'s shared tap.

local Core = require("CaddieCore")
local part = Core.part

local obj = {}
obj.__index = obj

obj.name = "TitleBarTweaks"
obj.version = "0.1.0"

-- Simulate Option while the cursor hovers the green button
obj.hoverOption = true
-- A title-bar double-click toggles, in place of the system's Fill or Zoom
obj.titleBarDoubleClick = true
-- Seconds to let a window settle after focusing it, before a toggle or a menu
-- command acts on it
obj.focusSettle = 0.05

part("toggle")(obj)
part("fullscreen")(obj)
part("hover")(obj)
part("clicks")(obj)

local types = hs.eventtap.event.types

function obj:init()
  Core.component(self)
  self:_declareFullscreen()
  self.physicalAlt, self.hoverAlt = false, false
  return self
end

function obj:start()
  if self.scope then return self end
  self.scope = Core.scope(self.name)
  self.scope:onShutdown(function() self:_releaseAlt() end)
  self.scope:add(function()
    if self.toggleTimer then self.toggleTimer:stop() end
    self.toggleTimer = nil
  end, "toggle timer")
  -- Taps are held on self, since a tap with no reference is garbage collected
  self.flagsTap = self.scope:eventtap({ types.flagsChanged },
    function(e) return self:_onFlags(e) end, "flags tap")
  -- CaddieTools starts this before EdgeSnap, so a click this swallows never arms a drag
  self.scope:add(Core.titlebar():subscribe(self.name, function(e) return self:_onClick(e) end), "title-bar clicks")
  if self.hoverOption then
    self.onHoverCheck = function() self:_hoverCheck() end
    self.onBoundsRefresh = function() self:_boundsRefreshed() end
    self.scope:add(function()
      if self.hoverTimer then self.hoverTimer:stop() end
      if self.boundsTimer then self.boundsTimer:stop() end
      self.hoverTimer, self.onHoverCheck, self.hoverPoint = nil, nil, nil
      self.boundsTimer, self.onBoundsRefresh, self.lastMovePoint = nil, nil, nil
    end, "hover check and bounds timers")
    self.moveTap = self.scope:eventtap({ types.mouseMoved },
      function(e) return self:_onMouseMoved(e) end, "hover tap")
  end
  return self
end

function obj:stop()
  self:_releaseAlt()
  if self.scope then self.scope:close() end
  self.scope, self.flagsTap, self.moveTap = nil, nil, nil
  self.clickMode = nil
  return self
end

return obj
