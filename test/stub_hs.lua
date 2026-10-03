-- stub_hs.lua
-- Minimal stand-in for the `hs` global so the Spoons can be loaded and their
-- logic exercised with standalone Lua. It fakes only what the Spoons touch,
-- records side effects in `hs._log`, and makes no attempt to model macOS.
--
-- Usage from a test file:
--   package.path = "<repo>/test/?.lua;" .. package.path
--   require("stub_hs").install("<repo>")

local M = {}

local function noop() end

local function fakeObject(label)
  local o = { label = label, running = false }
  function o:start() self.running = true return self end
  function o:stop() self.running = false return self end
  function o:delete() self.running = false end
  function o:isEnabled() return self.running end
  return o
end

local clock = 0

function M.install(root)
  local log = {}
  local settings = {}
  hs = {
    _log = log,
    configdir = "/tmp",
    printf = function(fmt, ...) print(string.format(fmt, ...)) end,
    alert = { show = function(msg) table.insert(log, "alert: " .. tostring(msg)) end },
    timer = {
      absoluteTime = function() clock = clock + 1000 return clock end,
      secondsSinceEpoch = function() return os.time() end,
      doEvery = function() return fakeObject("timer") end,
      doAfter = function(_, fn) fn() return fakeObject("timer") end,
      new = function() return fakeObject("timer") end,
    },
    hotkey = { bind = function(mods, key) return fakeObject("hotkey " .. key) end },
    eventtap = {
      new = function() return fakeObject("eventtap") end,
      event = {
        types = setmetatable({}, { __index = function(_, k) return k end }),
        properties = setmetatable({}, { __index = function(_, k) return k end }),
      },
    },
    screen = {
      allScreens = function() return {} end,
      mainScreen = function() return nil end,
      watcher = { new = function() return fakeObject("screen watcher") end },
    },
    window = {
      focusedWindow = function() return nil end,
      list = function() return {} end,
    },
    application = { watcher = { new = function() return fakeObject("app watcher") end } },
    json = {
      encode = function(t) return "<json>" end,
      decode = function() return {} end,
    },
    spoons = { resourcePath = function(p) return p end },
    settings = {
      get = function(k) return settings[k] end,
      set = function(k, v) settings[k] = v end,
    },
    geometry = { rect = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end },
    inspect = function(v) return tostring(v) end,
    shutdownCallback = nil,
  }
  spoon = {}
  if root then package.path = root .. "/Spoons/?.spoon/init.lua;" .. package.path end
  return hs
end

-- Loads a Spoon the way hs.loadSpoon does: require, call :init(), publish on `spoon`
function M.loadSpoon(name)
  local obj = require(name)
  if obj.init then obj:init() end
  spoon[name] = obj
  return obj
end

return M
