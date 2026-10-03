-- The window an action works on, read once per run into ctx.memo, and the result
-- and event payload every WindowState action shares

local M = {}

local function rect(r)
  if not r then return nil end
  return { x = r.x, y = r.y, w = r.w, h = r.h }
end
M.rect = rect

-- Fills the memo keys middleware reads, so no layer asks the window again. A caller
-- that already read the window's id or frame passes them in input. Returns the
-- window, or nil when there is none.
function M.load(ctx)
  local win = ctx:get("window", function(c) return c.input.window or hs.window.focusedWindow() end)
  if not win then return nil end
  ctx:get("windowID", function(c) return c.input.windowID or win:id() end)
  ctx:get("app", function()
    local app = win:application()
    return app and app:bundleID()
  end)
  ctx:get("currentFrame", function(c) return rect(c.input.currentFrame or win:frame()) end)
  return win
end

-- An EdgeSnap drop passes the frame from before the drag, so memory and undo see
-- where the window was rather than where the drag left it
function M.previousOf(ctx)
  return rect(ctx.input.previousFrame or ctx.memo.currentFrame)
end

function M.setFrame(win, f)
  win:setFrame(hs.geometry.rect(f.x, f.y, f.w, f.h), 0)
end

function M.snapshot(ctx, result)
  local m, p = ctx.memo, ctx.proposed
  return {
    spoon = ctx.spoon, action = ctx.action, status = result.status,
    reason = result.reason, by = result.by,
    source = ctx.input.source, kind = p.kind or ctx.action,
    -- The tile position placed, "maximize", or nil for anything else
    position = p.position,
    windowID = m.windowID, app = m.app,
    previousFrame = M.previousOf(ctx), finalFrame = rect(result.finalFrame),
    screenFrame = rect(p.screenFrame), screenID = result.screenID, movedScreen = result.movedScreen,
    mode = result.mode, method = result.method,
  }
end

-- Vetoed and early results come back from Core without the window fields, so they
-- are filled from the memo after the run
function M.complete(result, ctx)
  local m = ctx.memo
  if result.windowID == nil then result.windowID = m.windowID end
  if result.app == nil then result.app = m.app end
  if result.previousFrame == nil then result.previousFrame = M.previousOf(ctx) end
  return result
end

return M
