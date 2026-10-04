-- Real full screen, the Option-click. A Core action of this Spoon's own, since it is
-- not a placement WindowState knows about.

local Core = require("CaddieCore")

local rect = Core.rect

local function memoWindow(ctx, win)
  ctx:get("windowID", function() return win:id() end)
  local app = ctx:get("application", function() return win:application() end)
  ctx:get("app", function() return app and app:bundleID() end)
  ctx:get("currentFrame", function() return rect(win:frame()) end)
end

-- Vetoed and early results come back from Core without the window fields, so they
-- are filled from the memo
local function complete(result, ctx)
  local m = ctx.memo
  if result.windowID == nil then result.windowID = m.windowID end
  if result.app == nil then result.app = m.app end
  if result.previousFrame == nil then result.previousFrame = rect(m.currentFrame) end
  return result
end

local function snapshot(ctx, result)
  return {
    spoon = ctx.spoon, action = ctx.action, status = result.status,
    reason = result.reason, by = result.by,
    windowID = result.windowID or ctx.memo.windowID,
    app = result.app or ctx.memo.app,
    previousFrame = rect(result.previousFrame or ctx.memo.currentFrame),
  }
end

local function prepare(ctx)
  local w = ctx.input.window
  if not w then return { status = "unchanged", reason = "no window" } end
  memoWindow(ctx, w)
  if w:isFullScreen() then return { status = "unchanged", reason = "already full screen" } end
end

local function perform(ctx)
  ctx.input.window:setFullScreen(true)
  return { status = "completed", windowID = ctx:get("windowID"), app = ctx:get("app"),
    previousFrame = ctx:get("currentFrame") }
end

return function(obj)
  function obj:_declareFullscreen()
    self:action("fullscreen", { doc = "Enter real full screen", snapshot = snapshot })
  end

  function obj:fullscreen(win)
    return complete(self:run("fullscreen", { window = win or hs.window.focusedWindow() }, perform, prepare))
  end
end
