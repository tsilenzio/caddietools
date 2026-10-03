--- === CaddieCore ===
---
--- Shared runtime for the CaddieTools Spoons, each of which requires it, so it never
--- needs loading by hand. Gives a Spoon actions with a
--- per-action context, middleware with recorded owners, per-Spoon events carrying
--- snapshot payloads, structured results, and lifecycle scopes.
---
--- Allocation-reduced: chains are compiled when middleware is added or removed
--- rather than per call, the context creates `computed` and `errors` on first use,
--- and payloads are built only when someone is listening.
---
--- The runtime lives in runtime/, loaded through `CaddieCore.part`, which every Spoon
--- can use to load its own files.

local obj = {}
obj.__index = obj

obj.name = "CaddieCore"
obj.version = "0.1.0"
obj.protocol = 1

-- Parts --------------------------------------------------------------------------

local parts = {}    -- path -> what the file returned
local loaders = {}  -- .spoon directory -> its part function

-- `require` cannot reach inside a .spoon directory, since the dot in `.spoon` breaks
-- the module name. Each file is loaded once and receives its Spoon's part function
-- as `...`, so a part loads its siblings without requiring Core, which may still be
-- loading.
local function loaderFor(dir)
  local load = loaders[dir]
  if load then return load end
  load = function(relpath)
    local path = dir .. "/" .. relpath .. ".lua"
    if parts[path] == nil then
      parts[path] = assert(loadfile(path))(load)
    end
    return parts[path]
  end
  loaders[dir] = load
  return load
end

local function spoonDir(source)
  return source:match("^@(.*%.spoon)/")
end

local corePart = loaderFor(spoonDir(debug.getinfo(1, "S").source))

-- Loads <Name>.spoon/<relpath>.lua from the Spoon whose init.lua calls it, once
function obj.part(relpath)
  local source = debug.getinfo(2, "S").source
  local dir = spoonDir(source)
  assert(dir, "Core.part called from outside a .spoon directory: " .. source)
  local loaded = loaderFor(dir)(relpath)
  return loaded
end

local metrics = corePart("runtime/metrics")
local component = corePart("runtime/component")
local scope = corePart("runtime/scope")

-- Geometry -----------------------------------------------------------------------

-- Event payloads carry plain tables, never live hs.geometry or hs.window objects
function obj.rect(r)
  if not r then return nil end
  return { x = r.x, y = r.y, w = r.w, h = r.h }
end

-- Tile positions, monitor order, and screen-to-screen mapping, loaded on first use
-- so Spoons that never place windows never load it
function obj.geometry()
  return corePart("window/geometry")
end

local windowState = nil

-- The WindowState instance every window Spoon places through, created on first call
-- so Spoons that never place windows never load it
function obj.window()
  if not windowState then windowState = corePart("window/init").new() end
  return windowState
end

local titleBar = nil

-- The shared title-bar click and drag taps and window lookups, created on first call
function obj.titlebar()
  if not titleBar then titleBar = corePart("input/titlebar").new() end
  return titleBar
end

-- Components and scopes ------------------------------------------------------------

obj.component = component.mixin
obj.scope = scope.new

-- Shared state ---------------------------------------------------------------------

-- Screens change rarely, so one watcher keeps a cached list for every Spoon. It is
-- started by the first call, so nothing has to start CaddieCore by hand.
local screensCache = nil
local screenScope = nil

local function watchScreens()
  if screenScope then return end
  screenScope = obj.scope(obj.name)
  screenScope:watcher(hs.screen.watcher.new(function() screensCache = nil end), "screen watcher")
end

function obj.screens()
  watchScreens()
  if not screensCache then screensCache = hs.screen.allScreens() end
  return screensCache
end

-- Spoon lifecycle ------------------------------------------------------------------

-- Optional, since the watcher starts on first use. Kept so CaddieCore behaves like
-- any other Spoon when a config starts it.
function obj:start()
  watchScreens()
  return self
end

function obj:stop()
  if screenScope then screenScope:close() screenScope = nil end
  screensCache = nil
  return self
end

obj.inspect = corePart("runtime/inspect")
obj.metrics = metrics

return obj
