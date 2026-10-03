-- The restore and undo actions. Restore returns a window to its natural frame from
-- memory. Undo returns it to the frame it had before its last placement.

local part = ...
local target = part("window/target")
local memoryLib = part("window/memory")
local rect = target.rect

local M = {}

-- `memory` is the WindowState instance's store. Without a trusted natural frame, the
-- caller's input.fallback(win, ctx) returns a method and the frame to apply, or nil
-- for the frame when it moved the window itself. With no fallback either, the
-- restore is unchanged.
function M.prepareRestore(memory)
  return function(ctx)
    local win = target.load(ctx)
    if not win then return { status = "unchanged", reason = "no window" } end
    local screen = win:screen()
    if not screen then return { status = "unchanged", reason = "no screen" } end
    local p = ctx.proposed
    p.kind = "restore"
    p.screenFrame = rect(screen:frame())
    local e = memory:trusted(ctx.memo.windowID, ctx.memo.currentFrame)
    p.targetFrame = e and e.original and memoryLib.restoreFrame(e.original, p.screenFrame) or nil
    if not p.targetFrame and not ctx.input.fallback then
      return { status = "unchanged", reason = "no natural frame" }
    end
  end
end

function M.performRestore(ctx)
  local p, m = ctx.proposed, ctx.memo
  local method, final = "frame", p.targetFrame
  if not final then method, final = ctx.input.fallback(m.window, ctx) end
  if final then target.setFrame(m.window, final) end
  return {
    status = "completed", windowID = m.windowID, app = m.app, mode = "restore", method = method,
    -- A fallback such as an app's own menu command can animate, so its read-back
    -- may show an intermediate frame
    previousFrame = target.previousOf(ctx), finalFrame = rect(final) or rect(m.window:frame()),
  }
end

-- Peeks in prepare and pops in perform, so a vetoed undo keeps its frame
function M.prepareUndo(undo)
  return function(ctx)
    if not target.load(ctx) then return { status = "unchanged", reason = "no window" } end
    local frame = undo:peek(ctx.memo.windowID)
    if not frame then return { status = "unchanged", reason = "nothing to undo" } end
    local p = ctx.proposed
    p.kind = "undo"
    p.targetFrame = rect(frame)
  end
end

function M.performUndo(undo)
  return function(ctx)
    local p, m = ctx.proposed, ctx.memo
    undo:pop(m.windowID)
    target.setFrame(m.window, p.targetFrame)
    return {
      status = "completed", windowID = m.windowID, app = m.app,
      previousFrame = target.previousOf(ctx), finalFrame = rect(p.targetFrame),
    }
  end
end

return M
