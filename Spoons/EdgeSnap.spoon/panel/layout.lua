-- Where a panel goes: a line of three cells along an edge, or the L in a corner

local part = ...
local shape = part("panel/shape")

local M = {}

local EDGE_OFFSET, LABEL_GAP, LABEL_W, LABEL_H = shape.EDGE_OFFSET, shape.LABEL_GAP, shape.LABEL_W, shape.LABEL_H
local CORNERS = shape.CORNERS
local vertical, clamp, lineSize, lineCells = shape.vertical, shape.clamp, shape.lineSize, shape.lineCells
local spanOf, strip, canvasFrame = shape.spanOf, shape.strip, shape.canvasFrame

-- A line inside the usable frame `u` on `side`, centered on the cursor along the
-- edge and kept on screen. The top line sits under the menu bar. `full` is the
-- physical frame, which bounds the strip.
function M.layout(side, u, full, cursor)
  local w, h = lineSize(side)
  local x, y
  if vertical(side) then
    x = side == "left" and u.x + EDGE_OFFSET or u.x + u.w - EDGE_OFFSET - w
    y = clamp(math.floor(cursor.y - h / 2), u.y + EDGE_OFFSET, u.y + u.h - EDGE_OFFSET - h)
  else
    x = clamp(math.floor(cursor.x - w / 2), u.x + EDGE_OFFSET, u.x + u.w - EDGE_OFFSET - w)
    y = side == "top" and u.y + EDGE_OFFSET or u.y + u.h - EDGE_OFFSET - h
  end
  local panel = { x = x, y = y, w = w, h = h }
  local picker = {
    side = side, full = full, usable = u, panels = { panel }, rect = panel,
    cells = lineCells(side, x, y, panel),
    arms = { { side = side, strip = strip(side, panel, full), span = spanOf(side, panel), cells = { 1, 2, 3 } } },
  }
  picker.canvasFrame = canvasFrame(picker)
  return picker
end

-- An L in `corner` of the usable frame `u`: the side's column and the edge's row,
-- both tucked into the corner, so their corner cells land on the same spot and are
-- drawn once. The shared cell's label sits in the L's inner corner.
function M.layoutCorner(corner, u, full)
  local spec = CORNERS[corner]
  local vw, vh = lineSize(spec.side)
  local hw, hh = lineSize(spec.edge)
  local vx = spec.side == "left" and u.x + EDGE_OFFSET or u.x + u.w - EDGE_OFFSET - vw
  local hx = spec.side == "left" and u.x + EDGE_OFFSET or u.x + u.w - EDGE_OFFSET - hw
  local vy = spec.edge == "top" and u.y + EDGE_OFFSET or u.y + u.h - EDGE_OFFSET - vh
  local hy = spec.edge == "top" and u.y + EDGE_OFFSET or u.y + u.h - EDGE_OFFSET - hh
  local vPanel = { x = vx, y = vy, w = vw, h = vh }
  local hPanel = { x = hx, y = hy, w = hw, h = hh }
  local column = lineCells(spec.side, vx, vy, vPanel)
  local row = lineCells(spec.edge, hx, hy, hPanel)

  -- The column's corner cell is its top one for a top corner, its bottom one otherwise,
  -- and the row's is its left one for a left corner
  local colShared = spec.edge == "top" and 1 or 3
  local rowShared = spec.side == "left" and 1 or 3
  column[colShared].labelRect = {
    x = spec.side == "left" and vPanel.x + vPanel.w + LABEL_GAP or vPanel.x - LABEL_GAP - LABEL_W,
    y = spec.edge == "top" and hPanel.y + hPanel.h + LABEL_GAP or hPanel.y - LABEL_GAP - LABEL_H,
    w = LABEL_W, h = LABEL_H,
  }

  local cells, colIdx, rowIdx = {}, {}, {}
  for i, cell in ipairs(column) do
    cells[#cells + 1] = cell
    colIdx[i] = #cells
  end
  for i, cell in ipairs(row) do
    if i == rowShared then
      rowIdx[i] = colIdx[colShared]
    else
      cells[#cells + 1] = cell
      rowIdx[i] = #cells
    end
  end
  -- Each arm's span runs on past the panel to the screen corner, where nothing lies beyond
  local colSpan, rowSpan = spanOf(spec.side, vPanel), spanOf(spec.edge, hPanel)
  if spec.edge == "top" then colSpan[1] = full.y else colSpan[2] = full.y + full.h end
  if spec.side == "left" then rowSpan[1] = full.x else rowSpan[2] = full.x + full.w end
  local picker = {
    corner = corner, full = full, panels = { vPanel, hPanel }, cells = cells, shared = colIdx[colShared],
    arms = {
      { side = spec.side, strip = strip(spec.side, vPanel, full), span = colSpan, cells = colIdx },
      { side = spec.edge, strip = strip(spec.edge, hPanel, full), span = rowSpan, cells = rowIdx },
    },
  }
  picker.canvasFrame = canvasFrame(picker)
  return picker
end

-- The index of a placement in the panel, or nil when it is not one of its cells
function M.indexOf(picker, position)
  for i, cell in ipairs(picker.cells) do
    if cell.position == position then return i end
  end
  return nil
end

return M
