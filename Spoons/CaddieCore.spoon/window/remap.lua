-- Maps a window frame from one screen to another, keeping its position and size as
-- fractions of the screen. A border the window carries (the gap around a tile) is
-- removed first and put back after, so it stays the same width on any screen. The
-- border is a number for every side, or { left, top, right, bottom } when the gap
-- differs by side. A side flush with one screen's edge maps onto the other screen's
-- edge, so its zero border stays correct.

local M = {}

local function round(v)
  return math.floor(v + 0.5)
end

function M.remap(frame, from, to, border)
  local b = border or 0
  if type(b) == "number" then b = { left = b, top = b, right = b, bottom = b } end
  local l, t, r, bt = b.left or 0, b.top or 0, b.right or 0, b.bottom or 0
  local x, y = frame.x - l, frame.y - t
  local w, h = frame.w + l + r, frame.h + t + bt

  local out = {
    x = round(to.x + (x - from.x) / from.w * to.w),
    y = round(to.y + (y - from.y) / from.h * to.h),
    w = round(w / from.w * to.w),
    h = round(h / from.h * to.h),
  }
  out.x, out.y, out.w, out.h = out.x + l, out.y + t, out.w - l - r, out.h - t - bt
  return out
end

return M
