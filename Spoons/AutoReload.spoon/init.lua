--- === AutoReload ===
---
--- Reloads Hammerspoon when a .lua file under a watched directory is saved. Every
--- .lua file is compiled first, and a syntax error skips the reload, so the running
--- config stays up and the next save tries again. `:announce()` then says whether
--- the config loaded fresh or reloaded.
---
--- Uses no other Spoon, so a broken CaddieCore or profile cannot take hot reload down
--- with it.

local obj = {}
obj.__index = obj

obj.name = "AutoReload"
obj.version = "0.1.0"

-- Seconds after the last change before reloading. Editors often write a file in
-- several events.
obj.debounce = 0.3
-- Path fragments that are never watched or compiled
obj.ignored = { "/disabled/", "/.git/", "/results/" }
-- Seconds the loaded and reloaded alerts stay up
obj.alertSeconds = 2

-- Set just before hs.reload(), so the next load knows it was a reload
local FLAG = "AutoReload.reloading"

local function isIgnored(self, path)
  for _, fragment in ipairs(self.ignored) do
    if path:find(fragment, 1, true) then return true end
  end
  return false
end

local function luaFiles(self, dir, found)
  for name in hs.fs.dir(dir) do
    if name ~= "." and name ~= ".." then
      local path = dir .. "/" .. name
      local mode = hs.fs.attributes(path, "mode")
      if mode == "directory" and not isIgnored(self, path .. "/") then
        luaFiles(self, path, found)
      elseif mode == "file" and name:match("%.lua$") then
        table.insert(found, path)
      end
    end
  end
  return found
end

-- loadfile compiles without running, so this catches syntax errors only
function obj:_syntaxErrors()
  local errors = {}
  for _, root in ipairs(self.roots) do
    for _, path in ipairs(luaFiles(self, root, {})) do
      local ok, err = loadfile(path)
      if not ok then table.insert(errors, err) end
    end
  end
  return errors
end

function obj:_reloadIfValid()
  self.pending = nil
  local errors = self:_syntaxErrors()
  if #errors == 0 then
    hs.settings.set(FLAG, true)
    hs.reload()
    return
  end
  for _, err in ipairs(errors) do print("AutoReload: " .. err) end
  hs.alert.show("Config not reloaded: " .. errors[1]:gsub("^.*/", ""), 4)
end

function obj:_onChange(paths)
  for _, path in ipairs(paths) do
    if path:match("%.lua$") and not isIgnored(self, path) then
      if self.pending then self.pending:stop() end
      self.pending = hs.timer.doAfter(self.debounce, function() self:_reloadIfValid() end)
      return
    end
  end
end

function obj:_watcherFor(dir)
  return hs.pathwatcher.new(dir, function(paths) self:_onChange(paths) end):start()
end

-- Public API ------------------------------------------------------------------

function obj:init()
  self.roots = { hs.configdir }
  self.watchers = {}
end

-- Also watches dir. hs.pathwatcher does not follow symlinks, so code loaded from
-- outside the config directory has to be watched directly.
function obj:watch(dir)
  table.insert(self.roots, dir)
  if #self.watchers > 0 then table.insert(self.watchers, self:_watcherFor(dir)) end
  return self
end

function obj:start()
  if #self.watchers > 0 then return self end
  for _, dir in ipairs(self.roots) do table.insert(self.watchers, self:_watcherFor(dir)) end
  return self
end

function obj:stop()
  for _, w in ipairs(self.watchers) do w:stop() end
  self.watchers = {}
  if self.pending then self.pending:stop() end
  self.pending = nil
  return self
end

-- Called once the rest of the config has loaded
function obj:announce()
  local reloaded = hs.settings.get(FLAG)
  hs.settings.set(FLAG, nil)
  hs.alert.show(reloaded and "Hammerspoon config reloaded" or "Hammerspoon config loaded", self.alertSeconds)
  return self
end

return obj
