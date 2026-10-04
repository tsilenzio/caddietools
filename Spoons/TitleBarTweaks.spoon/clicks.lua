-- Clicks, through Core.titlebar()'s shared tap: a plain click on the green button and
-- a title-bar double-click toggle, and an Option-click on the button enters real
-- full screen.

local part = ...
local Core = require("CaddieCore")
local button = part("button")

local titleBar = Core.titlebar()
local types = hs.eventtap.event.types
local props = hs.eventtap.event.properties

-- Title-bar double-click. The band is the top of the window under the cursor, and
-- the element there must be window chrome rather than a control. Measured:
-- Chrome's tab strip and Ghostty's toolbar fill the top 40 pt and report
-- Window, Toolbar, TabGroup, Group, or StaticText, while content and the toolbar
-- controls below report TextArea, Button, TextField, or PopUpButton. Chrome reports
-- its tabs as Group too, so a double-click on a Chrome tab also counts.
local TITLE_BAR_H = titleBar.TITLE_BAR_H
local TITLE_BAR_ROLES = {
  AXWindow = true, AXToolbar = true, AXTabGroup = true, AXGroup = true,
  AXStaticText = true, AXImage = true,
}

return function(obj)
  -- The window whose title bar is at p, for the second click of a double-click. The
  -- Accessibility hit test runs inside the click tap, so it is reached only for a
  -- double-click in the top band of a window and costs 0.3 to 2.6 ms there.
  function obj:_titleBarWindow(p)
    local e, _, dy = titleBar:windowAt(p)
    if not e or dy >= TITLE_BAR_H then return nil end
    local ok, el = pcall(hs.axuielement.systemElementAtPosition, p)
    if not ok or not el or (e.pid and el:pid() ~= e.pid) then return nil end
    local role = el:attributeValue("AXRole")
    if not TITLE_BAR_ROLES[role] then return nil end
    local axWin = role == "AXWindow" and el or el:attributeValue("AXWindow")
    if not axWin or axWin:attributeValue("AXSubrole") ~= "AXStandardWindow" then return nil end
    return axWin:asHSWindow()
  end

  function obj:_onClick(event)
    local t = event:getType()
    if t == types.leftMouseDown then
      self.clickMode = nil
      local p = event:location()
      -- Refreshed in the tap, unlike hover, so a click on a window that just moved is
      -- never judged against its old position
      titleBar:refresh()
      local el = button.inCorner(p) and button.element(p)
      local axWin = el and el:attributeValue("AXWindow")
      local win = axWin and axWin:asHSWindow()
      if win then
        if self.physicalAlt then
          self.clickMode = "fullscreen"
        else
          self.clickMode = "toggle"
          self:_scheduleToggle(win)
          -- Swallowed so macOS does nothing itself
          return true
        end
      elseif self.titleBarDoubleClick and event:getProperty(props.mouseEventClickState) == 2 then
        win = self:_titleBarWindow(p)
        if win then
          -- Swallowed so the system's own double-click action (Fill or Zoom) never runs
          self.clickMode = "toggle"
          self:_scheduleToggle(win)
          return true
        end
      end
    end
    if self.clickMode == "toggle" then
      if t == types.leftMouseUp then self.clickMode = nil end
      return true
    end
    if self.clickMode == "fullscreen" then
      -- Option is stripped, real or simulated, so macOS enters full screen
      local flags = event:getFlags()
      flags.alt = nil
      event:setFlags(flags)
      if t == types.leftMouseUp then self.clickMode = nil end
    end
    return false
  end

  -- Runs after the tap returns, focused first so a menu fallback acts on this window.
  -- The timers are held on self, since an unreferenced timer can be collected first.
  function obj:_scheduleToggle(win)
    self.toggleTimer = hs.timer.doAfter(0, function()
      win:focus()
      self.toggleTimer = hs.timer.doAfter(self.focusSettle, function()
        self.toggleTimer = nil
        self:toggle(win)
      end)
    end)
  end
end
