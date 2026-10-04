-- The taps. A mouse down in a window's title band holds Core.titlebar()'s drag tap
-- until the mouse up, so drags that start anywhere else cost nothing more.

local Core = require("CaddieCore")

local titleBar = Core.titlebar()
local types = hs.eventtap.event.types
local rect = Core.rect
-- A drag counts only when it starts in the top band of a window, where title bars are
local TITLE_BAR_H = titleBar.TITLE_BAR_H

return function(obj)
  -- Nothing in the taps asks the window server or Accessibility. The lookups run
  -- from timers held on self after the tap returns.
  function obj:_onClick(event)
    if event:getType() == types.leftMouseDown then
      self:_endDrag()
      self.downPoint = event:location()
      self.downTimer = hs.timer.doAfter(0, self.onDown)
      return false
    end
    local target = self.target
    if target then self:_resolve(target, event:location()) end
    self:_endDrag()
    if target and target.confirmed and target.zone then
      self.dropTimer = hs.timer.doAfter(0, function()
        self.dropTimer = nil
        self:_drop(target)
      end)
    end
    return false
  end

  -- Holds the shared drag tap only for a mouse down in the title band of a window, so
  -- other drags add nothing. The refresh also updates the bounds every other title-bar
  -- subscriber reads.
  function obj:_down()
    self.downTimer = nil
    local p = self.downPoint
    if not p or self.releaseDrag then return end
    titleBar:refresh()
    local e, _, dy = titleBar:windowAt(p)
    if not e or dy >= TITLE_BAR_H then return end
    self.target = { id = e.id, pid = e.pid, start = rect(e.frame), down = p }
    local screens = {}
    for _, s in ipairs(Core.screens()) do
      screens[#screens + 1] = { screen = s, full = rect(s:fullFrame()), frame = rect(s:frame()) }
    end
    self.dragScreens = screens
    self.releaseDrag = titleBar:drag(self.name, self.onDrag)
  end

  function obj:_onDrag(event)
    local target = self.target
    if not target then return false end
    local p = event:location()
    if self.missionControlGuard then p = self:_guardTop(event, p) end
    if self:_resolve(target, p) then
      if not self.zoneTimer then self.zoneTimer = hs.timer.doAfter(0, self.onZone) end
    elseif target.followed and not self.followTimer then
      self.followTimer = hs.timer.doAfter(0, self.onFollow)
    end
    return false
  end

  function obj:_endDrag()
    if self.releaseDrag then self.releaseDrag() end
    self.releaseDrag, self.target, self.dragScreens, self.downPoint = nil, nil, nil, nil
    self.dragPrevY, self.guardUntil = nil, nil
    self:_releaseSeam()
    self:_hidePreview()
    self:_hidePicker()
  end

end
