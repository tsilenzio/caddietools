-- Run: lua test/test_autoreload.lua   (from the repo root)
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")
stub.install(".")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end

-- A fake tree of .lua files, where a file's source decides whether it compiles
local files = {}
local settings = {}
local reloads = 0
local watched = {}
local timers = {}

hs.configdir = "/cfg"
hs.fs = {
  dir = function(dir)
    local names, seen = {}, {}
    for path in pairs(files) do
      local rest = path:sub(#dir + 2)
      if path:sub(1, #dir + 1) == dir .. "/" then
        local name = rest:match("^[^/]+")
        if not seen[name] then seen[name] = true table.insert(names, name) end
      end
    end
    local i = 0
    return function() i = i + 1 return names[i] end
  end,
  attributes = function(path)
    if files[path] then return "file" end
    return "directory"
  end,
}
hs.settings = {
  get = function(k) return settings[k] end,
  set = function(k, v) settings[k] = v end,
}
hs.pathwatcher = {
  new = function(dir, fn)
    local w = { dir = dir, fn = fn, running = false }
    function w:start() self.running = true watched[dir] = self return self end
    function w:stop() self.running = false return self end
    return w
  end,
}
hs.timer.doAfter = function(_, fn)
  local t = { fn = fn, stopped = false }
  function t:stop() self.stopped = true end
  table.insert(timers, t)
  return t
end
hs.reload = function() reloads = reloads + 1 end

local realLoadfile = loadfile
loadfile = function(path)
  if files[path] == nil then return realLoadfile(path) end
  return load(files[path], "@" .. path)
end

local function fire()
  local pending = timers
  timers = {}
  for _, t in ipairs(pending) do if not t.stopped then t.fn() end end
end

local reload = stub.loadSpoon("AutoReload")
reload:watch("/repo"):start()
check(watched["/cfg"] and watched["/repo"], "watches the config directory and every added root")

-- A fresh start announces loaded
reload:announce()
check(hs._log[#hs._log] == "alert: Hammerspoon config loaded", "a fresh start says loaded")

-- A valid save reloads once, after the debounce, however many events arrive
files["/repo/a.lua"] = "return 1"
files["/repo/sub/b.lua"] = "return 2"
watched["/repo"].fn({ "/repo/a.lua" })
watched["/repo"].fn({ "/repo/a.lua", "/repo/sub/b.lua" })
check(reloads == 0, "nothing reloads before the debounce")
fire()
check(reloads == 1 and settings["AutoReload.reloading"] == true, "one reload, flagged as a reload")

-- The next load announces reloaded and clears the flag
reload:announce()
check(hs._log[#hs._log] == "alert: Hammerspoon config reloaded", "the next load says reloaded")
check(settings["AutoReload.reloading"] == nil, "the flag is cleared")

-- A syntax error anywhere skips the reload and names the file
files["/repo/sub/b.lua"] = "return ("
watched["/repo"].fn({ "/repo/sub/b.lua" })
fire()
check(reloads == 1, "a syntax error skips the reload")
check(hs._log[#hs._log]:find("Config not reloaded: b.lua", 1, true) ~= nil, "the alert names the broken file")

-- Ignored paths and non-Lua files do not schedule anything
files["/repo/sub/b.lua"] = "return 2"
watched["/repo"].fn({ "/repo/.git/index", "/repo/notes.md", "/repo/disabled/x.lua" })
check(#timers == 0, "ignored paths and non-Lua files are skipped")

reload:stop()
check(not watched["/cfg"].running and not watched["/repo"].running, "stop releases every watcher")

loadfile = realLoadfile
print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
