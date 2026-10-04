-- Drawing a panel into an hs.canvas

local part = ...
local geometry = require("CaddieCore").geometry()
local shape = part("panel/shape")

local M = {}

local ICON_W, ICON_H = shape.ICON_W, shape.ICON_H

-- The corners of an L's outline, clockwise, from its column V and row H, which share
-- the screen corner. The one vertex not on either panel's own corners is the L's
-- inner corner.
local function outlineOf(corner, V, H)
  local vr, vb, hr, hb = V.x + V.w, V.y + V.h, H.x + H.w, H.y + H.h
  if corner == "topLeft" then
    return { { V.x, V.y }, { hr, H.y }, { hr, hb }, { vr, hb }, { vr, vb }, { V.x, vb } }
  elseif corner == "topRight" then
    return { { H.x, H.y }, { vr, V.y }, { vr, vb }, { V.x, vb }, { V.x, hb }, { H.x, hb } }
  elseif corner == "bottomLeft" then
    return { { V.x, V.y }, { vr, V.y }, { vr, H.y }, { hr, H.y }, { hr, hb }, { V.x, vb } }
  end
  return { { V.x, V.y }, { vr, V.y }, { vr, vb }, { H.x, hb }, { H.x, H.y }, { V.x, H.y } }
end

-- Bezier weight that makes a cubic curve a close quarter circle
local ARC = 0.5523

-- hs.canvas segments for a closed polygon with every corner rounded by r, inner
-- corners included. Each corner is cut back r along both of its edges and the cut
-- joined by a curve whose control points lean toward the corner.
local function roundedPath(points, r, ox, oy)
  local n = #points
  local function cut(i, j)
    local px, py = points[i][1], points[i][2]
    local qx, qy = points[j][1], points[j][2]
    local len = math.sqrt((qx - px) ^ 2 + (qy - py) ^ 2)
    return px + (qx - px) * r / len, py + (qy - py) * r / len
  end
  local coords = {}
  for step = 0, n do
    local i = step % n + 1
    local prev, nxt = (i - 2) % n + 1, i % n + 1
    local ax, ay = cut(i, prev)
    local bx, by = cut(i, nxt)
    local px, py = points[i][1], points[i][2]
    if step > 0 then coords[#coords + 1] = { x = ax - ox, y = ay - oy } end
    local b = { x = bx - ox, y = by - oy }
    if step > 0 then
      b.c1x, b.c1y = ax + (px - ax) * ARC - ox, ay + (py - ay) * ARC - oy
      b.c2x, b.c2y = bx + (px - bx) * ARC - ox, by + (py - by) * ARC - oy
    end
    coords[#coords + 1] = b
  end
  return coords
end

local BLUE = { red = 0.2, green = 0.5, blue = 1, alpha = 1 }

local PANEL_RADIUS = 15
local PANEL_FILL = { white = 0.13, alpha = 0.92 }
local PANEL_STROKE = { white = 1, alpha = 0.35 }

-- Rebuilds every element, which happens only when the hovered cell changes. An L is
-- drawn as one outline of its whole shape, since two overlapping rounded rectangles
-- doubled the border where their edges ran together.
function M.render(canvas, picker, hovered, keepFrame)
  local o = picker.canvasFrame
  local function at(r) return { x = r.x - o.x, y = r.y - o.y, w = r.w, h = r.h } end
  local els = {}
  if picker.corner then
    local V, H = picker.panels[1], picker.panels[2]
    els[1] = {
      type = "segments", closed = true, action = "strokeAndFill",
      coordinates = roundedPath(outlineOf(picker.corner, V, H), PANEL_RADIUS, o.x, o.y),
      fillColor = PANEL_FILL, strokeColor = PANEL_STROKE, strokeWidth = 1,
    }
  else
    els[1] = {
      type = "rectangle", action = "strokeAndFill", frame = at(picker.panels[1]),
      roundedRectRadii = { xRadius = PANEL_RADIUS, yRadius = PANEL_RADIUS },
      fillColor = PANEL_FILL, strokeColor = PANEL_STROKE, strokeWidth = 1,
    }
  end
  for i, cell in ipairs(picker.cells) do
    local c, on = cell.rect, i == hovered
    if on then
      els[#els + 1] = {
        type = "rectangle", action = "strokeAndFill", frame = at(c),
        roundedRectRadii = { xRadius = 10, yRadius = 10 },
        fillColor = { red = 0.2, green = 0.45, blue = 1, alpha = 0.25 },
        strokeColor = { red = 0.2, green = 0.45, blue = 1, alpha = 0.6 }, strokeWidth = 1,
      }
    end
    local icon = { x = c.x + (c.w - ICON_W) / 2, y = c.y + (c.h - ICON_H) / 2, w = ICON_W, h = ICON_H }
    local innerIcon = { x = icon.x + 2, y = icon.y + 2, w = icon.w - 4, h = icon.h - 4 }
    els[#els + 1] = {
      type = "rectangle", action = "fill",
      frame = at(cell.position == "maximize" and innerIcon or geometry.baseTile(cell.position, innerIcon)),
      roundedRectRadii = { xRadius = 1.5, yRadius = 1.5 },
      fillColor = on and BLUE or { white = 1, alpha = 0.65 },
    }
    els[#els + 1] = {
      type = "rectangle", action = "stroke", frame = at(icon),
      roundedRectRadii = { xRadius = 3, yRadius = 3 },
      strokeColor = { white = 1, alpha = 0.85 }, strokeWidth = 1.5,
    }
  end
  local cell = hovered and picker.cells[hovered]
  if cell then
    local label = cell.labelRect
    els[#els + 1] = {
      type = "rectangle", action = "strokeAndFill", frame = at(label),
      roundedRectRadii = { xRadius = 7, yRadius = 7 },
      fillColor = { white = 0.15, alpha = 0.95 },
      strokeColor = { white = 1, alpha = 0.3 }, strokeWidth = 1,
    }
    els[#els + 1] = {
      type = "text", text = cell.label, frame = at({ x = label.x, y = label.y + 4, w = label.w, h = label.h - 4 }),
      textSize = 15, textColor = { white = 1, alpha = 1 }, textAlignment = "center",
    }
  end
  if not keepFrame then canvas:frame(o) end
  canvas:replaceElements(els)
end

function M.newCanvas()
  local c = hs.canvas.new({ x = 0, y = 0, w = 1, h = 1 })
  c:level(hs.canvas.windowLevels.overlay)
  c:behavior({ "canJoinAllSpaces", "transient" })
  return c
end

return M
