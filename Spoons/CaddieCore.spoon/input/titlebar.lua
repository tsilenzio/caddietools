-- One left-mouse click tap and one drag tap shared by every Spoon that acts on title
-- bars, instead of a tap each. Core.titlebar() creates it on first call.
--
-- The click tap exists while anyone is subscribed. Subscribers see each mouse down
-- and up in the order they subscribed, and one returning true swallows the event,
-- which also stops delivery to the rest. The drag tap exists only while someone
-- holds it, which in practice is while a title-bar drag is in progress.

local part = ...
local component = part("runtime/component")
local newScope = part("runtime/scope").new
local windows = part("input/windows")

local M = {}

local TitleBar = {}
TitleBar.__index = TitleBar

-- The top band of a window that counts as its title bar. Chrome's tab strip and
-- Ghostty's toolbar fill the top 40 pt, as measured.
TitleBar.TITLE_BAR_H = 40
TitleBar.windows = windows

local types = hs.eventtap.event.types
local now = hs.timer.absoluteTime

local function remove(list, entry)
  for i, e in ipairs(list) do
    if e == entry then table.remove(list, i) return end
  end
end

function M.new()
  local t = setmetatable({ name = "TitleBarInput", subscribers = {}, draggers = {}, boundsAt = 0 }, TitleBar)
  component.mixin(t)
  return t
end

function TitleBar:_onClick(event)
  for _, s in ipairs(self.subscribers) do
    if s.fn(event) then return true end
  end
  return false
end

function TitleBar:_onDrag(event)
  for _, d in ipairs(self.draggers) do d.fn(event) end
  return false
end

-- Returns a function that unsubscribes
function TitleBar:subscribe(owner, fn)
  local entry = { owner = owner, fn = fn }
  table.insert(self.subscribers, entry)
  if not self.scope then
    self.scope = newScope(self.name)
    -- Held on self, since a tap with no reference is garbage collected
    self.clickTap = self.scope:eventtap({ types.leftMouseDown, types.leftMouseUp },
      function(e) return self:_onClick(e) end, "click tap")
  end
  return function()
    remove(self.subscribers, entry)
    if #self.subscribers == 0 and self.scope then
      self.scope:close()
      self.scope, self.clickTap = nil, nil
    end
  end
end

-- Returns a function that releases the hold
function TitleBar:drag(owner, fn)
  local entry = { owner = owner, fn = fn }
  table.insert(self.draggers, entry)
  if not self.dragTap then
    self.dragTap = hs.eventtap.new({ types.leftMouseDragged }, function(e) return self:_onDrag(e) end):start()
  end
  return function()
    remove(self.draggers, entry)
    if #self.draggers == 0 and self.dragTap then
      self.dragTap:stop()
      self.dragTap = nil
    end
  end
end

-- Window bounds, cached for every subscriber. A refresh lists the windows again,
-- which costs 1.8 to 4 ms, so subscribers decide when that is worth it.
function TitleBar:refresh()
  self.bounds, self.boundsAt = windows.list(), now()
end

-- The window at p and p's offset into it, from the cached bounds as they stand
function TitleBar:windowAt(p)
  return windows.at(self.bounds, p)
end

return M
