-- The place action: puts a window at a frame its caller worked out, after the
-- WindowState rules and anyone else's middleware have shaped or vetoed it

local part = ...
local target = part("window/target")
local rect = target.rect

local M = {}

local KINDS = { tile = true, maximize = true, move = true }

function M.prepare(ctx)
  local input = ctx.input
  if not KINDS[input.kind] then return { status = "failed", reason = "unknown kind " .. tostring(input.kind) } end
  if not input.frame then return { status = "failed", reason = "no frame" } end
  if not target.load(ctx) then return { status = "unchanged", reason = "no window" } end
  local p = ctx.proposed
  p.kind = input.kind
  p.position = input.position
  p.targetFrame = rect(input.frame)
  p.screenFrame = rect(input.screenFrame)
  p.destinationScreen = input.screen
  p.movedScreen = input.movedScreen
end

-- The applied frame is reported rather than a read-back, which would cost another
-- Accessibility call
function M.perform(ctx)
  local p, m = ctx.proposed, ctx.memo
  target.setFrame(m.window, p.targetFrame)
  return {
    status = "completed", windowID = m.windowID, app = m.app,
    previousFrame = target.previousOf(ctx), finalFrame = rect(p.targetFrame),
    screenID = p.destinationScreen and p.destinationScreen:id(), movedScreen = p.movedScreen,
  }
end

return M
