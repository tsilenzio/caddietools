-- Panel geometry shared by layout, selection, the magnet, and drawing: sizes, the
-- cells each edge offers, and the rects a line is built from

local M = {}

-- Sized by the owner: cells 64 wide, everything else scaled with them
-- from the first 52 x 44 layout
M.CELL_W, M.CELL_H = 64, 54
M.PAD, M.GAP = 7, 5
M.EDGE_OFFSET = 4
M.LABEL_W, M.LABEL_H, M.LABEL_GAP = 128, 27, 10
M.ICON_W, M.ICON_H = 42, 27
-- An outline is stroked centered on its panel's edge, half of it outside, so the
-- canvas reaches this far past every panel or that half is clipped
M.STROKE_MARGIN = 2

M.LINES = {
  left = {
    { position = "topLeft", label = "Top left" },
    { position = "left", label = "Left side" },
    { position = "bottomLeft", label = "Bottom left" },
  },
  right = {
    { position = "topRight", label = "Top right" },
    { position = "right", label = "Right side" },
    { position = "bottomRight", label = "Bottom right" },
  },
  top = {
    { position = "topLeft", label = "Top left" },
    { position = "maximize", label = "Maximize" },
    { position = "topRight", label = "Top right" },
  },
  bottom = {
    { position = "bottomLeft", label = "Bottom left" },
    { position = "down", label = "Bottom half" },
    { position = "bottomRight", label = "Bottom right" },
  },
}

-- The two edges that meet at each corner
M.CORNERS = {
  topLeft = { side = "left", edge = "top" },
  topRight = { side = "right", edge = "top" },
  bottomLeft = { side = "left", edge = "bottom" },
  bottomRight = { side = "right", edge = "bottom" },
}

function M.vertical(side) return side == "left" or side == "right" end

function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function union(a, b)
  local x, y = math.min(a.x, b.x), math.min(a.y, b.y)
  return { x = x, y = y, w = math.max(a.x + a.w, b.x + b.w) - x, h = math.max(a.y + a.h, b.y + b.h) - y }
end

-- Size of a line's panel on `side`
function M.lineSize(side)
  if M.vertical(side) then return M.CELL_W + 2 * M.PAD, 3 * M.CELL_H + 2 * M.GAP + 2 * M.PAD end
  return 3 * M.CELL_W + 2 * M.GAP + 2 * M.PAD, M.CELL_H + 2 * M.PAD
end

-- The label for a cell of a line on `side`: beside a column, under or over a row
local function lineLabel(side, panel, c)
  if side == "left" then
    return { x = panel.x + panel.w + M.LABEL_GAP, y = c.y + (c.h - M.LABEL_H) / 2, w = M.LABEL_W, h = M.LABEL_H }
  elseif side == "right" then
    return { x = panel.x - M.LABEL_GAP - M.LABEL_W, y = c.y + (c.h - M.LABEL_H) / 2, w = M.LABEL_W, h = M.LABEL_H }
  end
  local y = side == "top" and panel.y + panel.h + M.LABEL_GAP or panel.y - M.LABEL_GAP - M.LABEL_H
  return { x = c.x + (c.w - M.LABEL_W) / 2, y = y, w = M.LABEL_W, h = M.LABEL_H }
end

-- The cells of a line on `side` whose panel is at (x, y), each with its label
function M.lineCells(side, x, y, panel)
  local cells = {}
  for i, spec in ipairs(M.LINES[side]) do
    local cx, cy = x + M.PAD, y + M.PAD
    if M.vertical(side) then cy = cy + (i - 1) * (M.CELL_H + M.GAP) else cx = cx + (i - 1) * (M.CELL_W + M.GAP) end
    local rect = { x = cx, y = cy, w = M.CELL_W, h = M.CELL_H }
    cells[i] = { position = spec.position, label = spec.label, rect = rect, labelRect = lineLabel(side, panel, rect) }
  end
  return cells
end

-- The stretch along the edge where a panel's cells select: its own length
function M.spanOf(side, panel)
  if M.vertical(side) then return { panel.y, panel.y + panel.h } end
  return { panel.x, panel.x + panel.w }
end

-- The strip a line selects across: from the physical screen edge to the panel's
-- far side, the whole length of the edge
function M.strip(side, panel, f)
  if side == "left" then return { x = f.x, y = f.y, w = panel.x + panel.w - f.x, h = f.h } end
  if side == "right" then return { x = panel.x, y = f.y, w = f.x + f.w - panel.x, h = f.h } end
  if side == "top" then return { x = f.x, y = f.y, w = f.w, h = panel.y + panel.h - f.y } end
  return { x = f.x, y = panel.y, w = f.w, h = f.y + f.h - panel.y }
end

-- The canvas covers every panel, with its outline, and every label a hover can show
function M.canvasFrame(picker)
  local frame = nil
  for _, panel in ipairs(picker.panels) do
    local m = M.STROKE_MARGIN
    local outlined = { x = panel.x - m, y = panel.y - m, w = panel.w + 2 * m, h = panel.h + 2 * m }
    frame = frame and union(frame, outlined) or outlined
  end
  for _, cell in ipairs(picker.cells) do frame = union(frame, cell.labelRect) end
  return frame
end

function M.inside(f, p)
  return p.x >= f.x and p.y >= f.y and p.x < f.x + f.w and p.y < f.y + f.h
end

return M
