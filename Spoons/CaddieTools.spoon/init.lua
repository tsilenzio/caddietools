--- === CaddieTools ===
---
--- Loads, configures, and starts the CaddieTools Spoons in one call:
---
---   hs.loadSpoon("CaddieTools").use({ "TileManager", "TitleBarTweaks", "EdgeSnap", "MouseTweaks" })
---
--- A name on its own uses that Spoon with its defaults, default hotkeys included. A
--- name with a table takes these options:
---   config   values set on the Spoon before it starts, merged into tables it has
---   hotkeys  "default" for the Spoon's defaultHotkeys, or a mapping for bindHotkeys
---   start    false to load and configure without starting
---   watch    AutoReload only: a directory or list of directories to watch as well
--- `WindowState = { config = { gap = 4 } }` sets CaddieCore.window()'s settings.
---
--- The other Spoons are loaded from the directory this one sits in, so they work
--- installed into ~/.hammerspoon/Spoons or straight from a checkout with
---   dofile("/path/to/Spoons/CaddieTools.spoon/init.lua").use({ ... })
--- CaddieCore loads with the first Spoon that needs it.

local obj = {}
obj.__index = obj

obj.name = "CaddieTools"
obj.version = "0.1.0"

local OPTIONS = { config = true, hotkeys = true, start = true, watch = true }

-- Started in this order whatever order they are listed in. Ties keep the list's
-- order, and named entries, which a Lua table holds in no order, come after the list
-- by name. AutoReload first, so an error further on still leaves hot reload running.
-- TitleBarTweaks subscribes to the shared click tap before EdgeSnap, so a click it
-- swallows never arms a drag.
local RANK = { AutoReload = 0, EdgeSnap = 2 }

local thisDir = debug.getinfo(1, "S").source:match("^@(.*)/init%.lua$")
local spoonsDir = thisDir and thisDir:match("^(.*)/[^/]+%.spoon$")
if spoonsDir then
  local entry = spoonsDir .. "/?.spoon/init.lua"
  if not package.path:find(entry, 1, true) then package.path = entry .. ";" .. package.path end
end

-- The checkout this Spoon really lives in, when it is symlinked into the config
-- directory. hs.pathwatcher does not follow symlinks, so AutoReload has to watch it
-- directly for edits there to reload.
local function checkoutRoot()
  local real = thisDir and hs.fs and hs.fs.pathToAbsolute and hs.fs.pathToAbsolute(thisDir)
  local root = real and real:match("^(.*)/Spoons/[^/]+%.spoon$")
  local config = hs.fs and hs.fs.pathToAbsolute and hs.fs.pathToAbsolute(hs.configdir) or hs.configdir
  if not root or root:sub(1, #config) == config then return nil end
  return root
end

-- Tables merge into tables the Spoon already has, so { smooth = { enabled = false } }
-- leaves smooth's other settings alone
local function merge(into, from)
  for k, v in pairs(from) do
    if type(v) == "table" and type(into[k]) == "table" then merge(into[k], v) else into[k] = v end
  end
end

-- Each entry as { name, opts, plain }, in start order
local function entries(spec)
  local list, named = {}, {}
  for i, v in ipairs(spec) do
    assert(type(v) == "string", "CaddieTools: list entries are Spoon names, got " .. type(v))
    list[#list + 1] = { name = v, opts = {}, plain = true, order = i }
  end
  for k, v in pairs(spec) do
    if type(k) == "string" then named[#named + 1] = k end
  end
  table.sort(named)
  for i, name in ipairs(named) do
    local opts = spec[name]
    if opts == true then opts = {} end
    assert(type(opts) == "table", "CaddieTools: options for " .. name .. " must be a table")
    for key in pairs(opts) do
      assert(OPTIONS[key], "CaddieTools: unknown option " .. tostring(key) .. " for " .. name)
    end
    list[#list + 1] = { name = name, opts = opts, plain = false, order = #spec + i }
  end
  table.sort(list, function(a, b)
    local ra, rb = RANK[a.name] or 1, RANK[b.name] or 1
    if ra ~= rb then return ra < rb end
    return a.order < b.order
  end)
  return list
end

local function useOne(e, started)
  local opts = e.opts
  if e.name == "WindowState" then
    local state = require("CaddieCore").window()
    if opts.config then merge(state, opts.config) end
    started.WindowState = state
    return
  end
  local s = hs.loadSpoon(e.name)
  assert(s, "CaddieTools: no Spoon named " .. e.name)
  if opts.config then merge(s, opts.config) end
  local hotkeys = opts.hotkeys
  if hotkeys == nil and e.plain then hotkeys = s.defaultHotkeys and "default" end
  if hotkeys == "default" then
    hotkeys = assert(s.defaultHotkeys, "CaddieTools: " .. e.name .. " has no defaultHotkeys")
  end
  if hotkeys then s:bindHotkeys(hotkeys) end
  if e.name == "AutoReload" then
    local watch = opts.watch
    if type(watch) == "string" then watch = { watch } end
    for _, dir in ipairs(watch or {}) do s:watch(dir) end
    local root = checkoutRoot()
    if root then s:watch(root) end
  end
  if opts.start ~= false and s.start then s:start() end
  started[e.name] = s
end

-- Returns the Spoons it used, by name. Takes `obj.use(spec)` or `obj:use(spec)`.
function obj.use(spec, more)
  if spec == obj then spec = more end
  local started = {}
  for _, e in ipairs(entries(spec or {})) do useOne(e, started) end
  if started.AutoReload then started.AutoReload:announce() end
  return started
end

return obj
