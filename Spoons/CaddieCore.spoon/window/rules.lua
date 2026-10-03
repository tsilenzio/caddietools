-- The placement rules WindowState applies as its own middleware, each driven by one
-- setting and off while that setting is nil or empty. Registered in this order, so
-- the guard on the final size sees what the transforms produced.

local M = {}

-- Edges within this many points of the screen edge count as flush, for screens
-- whose frames are not whole points
local FLUSH = 0.5

local function appOf(ctx)
  return ctx:get("app", function(c)
    local win = c.memo.window
    local app = win and win:application()
    return app and app:bundleID()
  end)
end

-- Vetoes every action on windows of the listed apps
function M.excluded(settings, app)
  local excluded = settings.excluded
  if app and excluded and excluded[app] then return false, "excluded app " .. app end
  return true
end

-- A maximize for a listed app takes a fraction of the screen, centered on it
function M.preset(settings, app, frame, screenFrame)
  local preset = app and settings.presets and settings.presets[app]
  if not preset or not screenFrame then return frame end
  local w, h = screenFrame.w * preset.w, screenFrame.h * preset.h
  return {
    x = screenFrame.x + (screenFrame.w - w) / 2,
    y = screenFrame.y + (screenFrame.h - h) / 2,
    w = w, h = h,
  }
end

-- A tile for a listed app shrinks to a fraction of the tile, centered in it
function M.centerSmall(settings, app, frame)
  local cs = settings.centerSmall
  if not (app and frame and cs and cs.apps and cs.apps[app]) then return frame end
  local w, h = frame.w * cs.fraction, frame.h * cs.fraction
  return {
    x = frame.x + (frame.w - w) / 2,
    y = frame.y + (frame.h - h) / 2,
    w = w, h = h,
  }
end

local function inset(edge, screenEdge, g)
  if screenEdge and math.abs(edge - screenEdge) <= FLUSH then return 0 end
  return g
end

-- Insets each side that is not flush with the screen edge by the gap. A maximized
-- window fills the screen, and a left half touches the left, top, and bottom edges
-- with its gap only on the right, so two windows sharing an edge end up 2 * gap
-- apart. Without a screen frame every side is inset.
function M.gap(settings, frame, screenFrame)
  local g = settings.gap or 0
  if not frame or g == 0 then return frame end
  local sf = screenFrame or {}
  local l = inset(frame.x, sf.x, g)
  local t = inset(frame.y, sf.y, g)
  local r = inset(frame.x + frame.w, sf.x and sf.x + sf.w, g)
  local b = inset(frame.y + frame.h, sf.y and sf.y + sf.h, g)
  return { x = frame.x + l, y = frame.y + t, w = frame.w - l - r, h = frame.h - t - b }
end

-- Vetoes frames smaller than the minimum
function M.minimum(settings, frame)
  local min = settings.minSize
  if not frame or not min then return true end
  if frame.w < min.w or frame.h < min.h then
    return false, string.format("frame %dx%d below minimum %dx%d",
      math.floor(frame.w), math.floor(frame.h), min.w, min.h)
  end
  return true
end

-- Moves keep the border they carry, and a restore or undo returns a frame the
-- window already had, so the shaping rules act on tiles and maximizes only
local SHAPED = { tile = true, maximize = true }

-- `s` is the WindowState instance, which also carries the settings
function M.install(s)
  local function opts(kind, name) return { kind = kind, owner = s.name, name = name } end

  local function exclude(ctx) return M.excluded(s, appOf(ctx)) end
  for _, action in ipairs({ "place", "restore", "undo" }) do
    s:use(action, exclude, opts("guard", "exclude"))
  end

  s:use("place", function(ctx)
    local p = ctx.proposed
    if p.kind == "maximize" and p.targetFrame then
      p.targetFrame = M.preset(s, appOf(ctx), p.targetFrame, p.screenFrame)
    end
  end, opts("transform", "preset"))

  s:use("place", function(ctx)
    local p = ctx.proposed
    if p.kind == "tile" and p.targetFrame then p.targetFrame = M.centerSmall(s, appOf(ctx), p.targetFrame) end
  end, opts("transform", "center"))

  s:use("place", function(ctx)
    local p = ctx.proposed
    if SHAPED[p.kind] and p.targetFrame then p.targetFrame = M.gap(s, p.targetFrame, p.screenFrame) end
  end, opts("transform", "gap"))

  s:use("place", function(ctx)
    local p = ctx.proposed
    if SHAPED[p.kind] then return M.minimum(s, p.targetFrame) end
  end, opts("guard", "minimum"))
end

return M
