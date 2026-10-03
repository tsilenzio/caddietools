-- Lifecycle scopes: everything a Spoon creates is registered on one, and closing it
-- releases them in reverse order

local part = ...
local addShutdown = part("runtime/shutdown").add

local Scope = {}
Scope.__index = Scope

local M = {}

function M.new(owner)
  return setmetatable({ owner = owner, items = {} }, Scope)
end

function Scope:add(release, label)
  table.insert(self.items, { release = release, label = label or "resource" })
  return release
end

function Scope:hotkey(mods, key, pressed, released, repeated)
  local hk = hs.hotkey.bind(mods, key, pressed, released, repeated)
  self:add(function() hk:delete() end, "hotkey " .. table.concat(mods, "+") .. "+" .. key)
  return hk
end

function Scope:eventtap(types, fn, label)
  local tap = hs.eventtap.new(types, fn):start()
  self:add(function() tap:stop() end, label or "eventtap")
  return tap
end

-- One-shot timer, cancelled on close if it has not fired yet
function Scope:after(seconds, fn, label)
  local t = hs.timer.doAfter(seconds, fn)
  self:add(function() t:stop() end, label or ("one-shot " .. seconds .. "s"))
  return t
end

function Scope:every(seconds, fn, label)
  local t = hs.timer.doEvery(seconds, fn)
  self:add(function() t:stop() end, label or ("timer " .. seconds .. "s"))
  return t
end

-- Anything with a :stop() method, such as hs.screen.watcher or hs.application.watcher
function Scope:watcher(w, label)
  w:start()
  self:add(function() w:stop() end, label or "watcher")
  return w
end

function Scope:onShutdown(fn)
  return self:add(addShutdown(fn), "shutdown handler")
end

function Scope:close()
  for i = #self.items, 1, -1 do
    local ok, err = pcall(self.items[i].release)
    if not ok then print(string.format("Core: %s failed releasing %s: %s", self.owner, self.items[i].label, err)) end
  end
  self.items = {}
end

function Scope:list()
  local labels = {}
  for i, item in ipairs(self.items) do labels[i] = item.label end
  return labels
end

return M
