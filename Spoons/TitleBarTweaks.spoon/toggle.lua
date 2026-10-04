-- The toggle: maximize, or restore a window that is maximized. Both go through
-- Core.window() with source "titlebar", so the maximize gets the same presets and
-- gap as TileManager's. With no natural frame in WindowState's memory, a restore
-- falls back to the app's Return to Previous Size, then to two thirds of the screen.

local Core = require("CaddieCore")

local rect = Core.rect

local RESTORE_PATHS = {
  { "Window", "Move & Resize", "Return to Previous Size" },
  { "Window", "Return to Previous Size" },
}

local function tryMenu(app, paths)
  if not app then return false end
  for _, path in ipairs(paths) do
    local item = app:findMenuItem(path)
    if item and item.enabled and app:selectMenuItem(path) then return true end
  end
  return false
end

-- Maximized means filling the usable frame of its screen, within the slack TileManager
-- uses for repeat detection
local function nearFrame(a, b)
  local s = 20
  return math.abs(a.x - b.x) <= s and math.abs(a.y - b.y) <= s
    and math.abs(a.x + a.w - b.x - b.w) <= s and math.abs(a.y + a.h - b.y - b.h) <= s
end

-- Two thirds of the screen, centered, for a restore with nothing better to go on
local function defaultFrame(sf)
  local w, h = math.floor(sf.w * 2 / 3), math.floor(sf.h * 2 / 3)
  return { x = sf.x + math.floor((sf.w - w) / 2), y = sf.y + math.floor((sf.h - h) / 2), w = w, h = h }
end

return function(obj)
  -- Menu commands act on the app's focused window
  function obj:_ensureFocused(win)
    local focused = hs.window.focusedWindow()
    if focused and focused:id() == win:id() then return end
    win:focus()
    hs.timer.usleep(self.focusSettle * 1e6)
  end

  -- A menu restore reports no frame, so WindowState reads the window back
  function obj:_restoreFallback(win, ctx)
    self:_ensureFocused(win)
    if tryMenu(win:application(), RESTORE_PATHS) then return "menu", nil end
    return "default", defaultFrame(ctx.proposed.screenFrame)
  end

  -- Maximized means placed as a maximize and not moved since, which also covers an
  -- app preset that does not fill its screen, or filling the screen by geometry
  function obj:toggle(win)
    win = win or hs.window.focusedWindow()
    if not win then return { status = "unchanged", reason = "no window" } end
    local screen = win:screen()
    if not screen then return { status = "unchanged", reason = "no screen", windowID = win:id() } end
    local state = Core.window()
    local id, current, sf = win:id(), rect(win:frame()), rect(screen:frame())
    local e = state:trusted(id, current)
    local result
    if (e and e.applied.kind == "maximize") or nearFrame(current, sf) then
      result = state:restore(win, {
        source = "titlebar", windowID = id, currentFrame = current,
        fallback = function(w, ctx) return self:_restoreFallback(w, ctx) end,
      })
      result.mode = "restore"
    else
      result = state:place(win, {
        kind = "maximize", position = "maximize", frame = sf, screenFrame = sf, screen = screen,
        windowID = id, currentFrame = current, source = "titlebar",
      })
      result.mode, result.method = "maximize", result.status == "completed" and "frame" or nil
    end
    return result
  end
end
