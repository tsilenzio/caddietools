-- Window lookups by point and by id, from hs.window.list(). That call takes 1.8 to
-- 4 ms, so callers in an event tap keep to a cached list.

local M = {}

-- Normal windows front to back, each { id, pid, frame }
function M.list()
  local out = {}
  for _, info in ipairs(hs.window.list() or {}) do
    local b = info.kCGWindowBounds
    if b and (info.kCGWindowLayer or 0) == 0 then
      out[#out + 1] = {
        id = info.kCGWindowNumber, pid = info.kCGWindowOwnerPID,
        frame = { x = b.X, y = b.Y, w = b.Width, h = b.Height },
      }
    end
  end
  return out
end

-- The list runs front to back, so the first window containing p is the one the
-- cursor is over. Returns it and p's offset into it.
function M.at(list, p)
  for _, e in ipairs(list or {}) do
    local f = e.frame
    local dx, dy = p.x - f.x, p.y - f.y
    if dx >= 0 and dy >= 0 and dx < f.w and dy < f.h then return e, dx, dy end
  end
  return nil
end

function M.boundsOf(id)
  for _, info in ipairs(hs.window.list() or {}) do
    local b = info.kCGWindowBounds
    if info.kCGWindowNumber == id and b then return { x = b.X, y = b.Y, w = b.Width, h = b.Height } end
  end
  return nil
end

-- A clicked window is almost always focused by the click. The app's own windows are
-- the fallback for the rare one that is not.
function M.windowFor(id, pid)
  local focused = hs.window.focusedWindow()
  if focused and focused:id() == id then return focused end
  local app = pid and hs.application.applicationForPID(pid)
  for _, w in ipairs(app and app:allWindows() or {}) do
    if w:id() == id then return w end
  end
  return nil
end

return M
