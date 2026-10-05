-- Run: lua test/test_caddietools.lua   (from the repo root)
-- CaddieTools' use(): finding its sibling Spoons, start order, default hotkeys,
-- config merging, WindowState settings, and AutoReload watching the checkout.
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end

local started, bound, watched

-- Without a root, the stub adds no Spoons directory, so CaddieTools has to add its own
local function boot()
  for name in pairs(package.loaded) do
    if name:match("^%u%a+$") then package.loaded[name] = nil end
  end
  stub.install(nil)
  started, bound, watched = {}, {}, {}
  hs.configdir = "/cfg"
  hs.canvas = { new = function() local c = {} setmetatable(c, { __index = function() return function() return c end end }) return c end,
    windowLevels = { overlay = 0 } }
  hs.hotkey.bind = function(mods, key) bound[#bound + 1] = key return { delete = function() end } end
  hs.pathwatcher = { new = function(dir)
    watched[#watched + 1] = dir
    return { start = function(s) return s end, stop = function() end }
  end }
  hs.fs = {
    dir = function() return function() return nil end end,
    attributes = function() return nil end,
    -- As if CaddieTools.spoon were a symlink from the config directory into a checkout
    pathToAbsolute = function(p)
      if p:match("CaddieTools%.spoon$") then return "/repo/Spoons/CaddieTools.spoon" end
      return p
    end,
  }
  -- hs.loadSpoon as Hammerspoon has it: require, init, publish on `spoon`, and nil for
  -- a name it cannot find. Every start is recorded in order.
  hs.loadSpoon = function(name)
    if spoon[name] then return spoon[name] end
    local ok, obj = pcall(require, name)
    if not ok then return nil end
    if obj.init then obj:init() end
    local start = obj.start
    if start then
      obj.start = function(self, ...)
        started[#started + 1] = name
        return start(self, ...)
      end
    end
    spoon[name] = obj
    return obj
  end
  return dofile("Spoons/CaddieTools.spoon/init.lua")
end

local caddie = boot()
check(package.path:find("Spoons/?.spoon/init.lua", 1, true) ~= nil, "loading CaddieTools puts its sibling Spoons on the path")

local used = caddie.use({ "EdgeSnap", "MouseTweaks", "TitleBarTweaks", "TileManager", "AutoReload" })
check(table.concat(started, ",") == "AutoReload,MouseTweaks,TitleBarTweaks,TileManager,EdgeSnap",
  "AutoReload starts first and EdgeSnap after TitleBarTweaks, the rest in list order, got " .. table.concat(started, ","))
local subs = require("CaddieCore").titlebar().subscribers
check(subs[1].owner == "TitleBarTweaks" and subs[2].owner == "EdgeSnap", "TitleBarTweaks gets clicks before EdgeSnap")
check(#bound == 16, "a TileManager named on its own binds its 16 default hotkeys, got " .. #bound)
check(used.TileManager and used.EdgeSnap and used.MouseTweaks and used.TitleBarTweaks, "use returns the Spoons by name")
check(hs._log[#hs._log] == "alert: Hammerspoon config loaded", "AutoReload announces once everything is up")
local repoWatched = false
for _, dir in ipairs(watched) do if dir == "/repo" then repoWatched = true end end
check(repoWatched, "AutoReload watches the checkout a symlinked CaddieTools really lives in")

-- Options
caddie = boot()
used = caddie:use({
  WindowState = { config = { gap = 4, excluded = { ["com.example.x"] = true } } },
  TileManager = {},
  MouseTweaks = { config = { smooth = { enabled = false } } },
  EdgeSnap = { start = false },
})
local state = require("CaddieCore").window()
check(used.WindowState == state and state.gap == 4 and state.excluded["com.example.x"], "WindowState config sets CaddieCore.window()'s settings")
check(#bound == 0, "a TileManager given a table and no hotkeys binds none")
check(used.MouseTweaks.smooth.enabled == false and used.MouseTweaks.smooth.tau == 0.09,
  "config merges into a Spoon's tables, keeping the settings it does not name")
check(table.concat(started, ",") == "MouseTweaks,TileManager", "start = false loads without starting, named entries in name order, got " .. table.concat(started, ","))
check(used.EdgeSnap ~= nil, "and still returns it")

caddie = boot()
caddie.use({ TileManager = { hotkeys = { left = { { "cmd" }, "h" } } } })
check(#bound == 1 and bound[1] == "h", "a hotkeys table binds that mapping")

-- Mistakes fail loudly
caddie = boot()
local ok, err = pcall(caddie.use, { TileManager = { hotkey = "default" } })
check(not ok and err:find("unknown option hotkey for TileManager", 1, true), "an unknown option is an error")
ok, err = pcall(caddie.use, { "NoSuchSpoon" })
check(not ok and err:find("no Spoon named NoSuchSpoon", 1, true), "an unknown Spoon is an error")
ok, err = pcall(caddie.use, { MouseTweaks = { hotkeys = "default" } })
check(not ok and err:find("MouseTweaks has no defaultHotkeys", 1, true), "default hotkeys on a Spoon without them is an error")

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
