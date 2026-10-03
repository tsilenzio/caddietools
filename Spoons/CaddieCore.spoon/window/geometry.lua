-- Tile geometry and monitor order shared by the window Spoons, through
-- Core.geometry(). Pure Lua, so it can be tested without Hammerspoon.

local part = ...

local M = {}

M.remap = part("window/remap").remap

-- Frames within this many points count as the same, for repeat detection and for
-- monitors whose edges macOS reports a few points apart
M.SLACK = 20

function M.rect(r)
  if not r then return nil end
  return { x = r.x, y = r.y, w = r.w, h = r.h }
end

function M.near(a, b)
  local s = M.SLACK
  return math.abs(a.x - b.x) <= s and math.abs(a.y - b.y) <= s
    and math.abs(a.x + a.w - b.x - b.w) <= s
    and math.abs(a.y + a.h - b.y - b.h) <= s
end

-- Positions --------------------------------------------------------------------

-- Every position repeats the same way: pressed again while the window is already
-- there, it moves to the next monitor in the same position. step is the direction
-- through the monitor order, and only left goes backward.
M.POSITIONS = {
  left = { step = -1 }, right = { step = 1 }, up = { step = 1 }, down = { step = 1 },
  topLeft = { step = 1 }, topRight = { step = 1 }, bottomLeft = { step = 1 }, bottomRight = { step = 1 },
  firstThird = { step = 1 }, centerThird = { step = 1 }, lastThird = { step = 1 },
  firstTwoThirds = { step = 1 }, centerTwoThirds = { step = 1 }, lastTwoThirds = { step = 1 },
}

-- Cumulative boundaries, so adjacent tiles share an edge with no rounding gap
local function cut(start, length, fraction)
  return start + math.floor(length * fraction)
end

-- Thirds run along the long side, so a portrait screen gets top, middle, bottom
local function span(sf, from, to)
  if sf.h > sf.w then
    local y1, y2 = cut(sf.y, sf.h, from), cut(sf.y, sf.h, to)
    if to == 1 then y2 = sf.y + sf.h end
    return { x = sf.x, y = y1, w = sf.w, h = y2 - y1 }
  end
  local x1, x2 = cut(sf.x, sf.w, from), cut(sf.x, sf.w, to)
  if to == 1 then x2 = sf.x + sf.w end
  return { x = x1, y = sf.y, w = x2 - x1, h = sf.h }
end

function M.baseTile(position, sf)
  local halfW, halfH = math.floor(sf.w / 2), math.floor(sf.h / 2)
  local left = { x = sf.x, w = halfW }
  local right = { x = sf.x + halfW, w = sf.w - halfW }
  local top = { y = sf.y, h = halfH }
  local bottom = { y = sf.y + halfH, h = sf.h - halfH }

  if position == "maximize" then return M.rect(sf) end
  if position == "left" then return { x = left.x, y = sf.y, w = left.w, h = sf.h } end
  if position == "right" then return { x = right.x, y = sf.y, w = right.w, h = sf.h } end
  if position == "up" then return { x = sf.x, y = top.y, w = sf.w, h = top.h } end
  if position == "down" then return { x = sf.x, y = bottom.y, w = sf.w, h = bottom.h } end
  if position == "topLeft" then return { x = left.x, y = top.y, w = left.w, h = top.h } end
  if position == "topRight" then return { x = right.x, y = top.y, w = right.w, h = top.h } end
  if position == "bottomLeft" then return { x = left.x, y = bottom.y, w = left.w, h = bottom.h } end
  if position == "bottomRight" then return { x = right.x, y = bottom.y, w = right.w, h = bottom.h } end
  if position == "firstThird" then return span(sf, 0, 1 / 3) end
  if position == "centerThird" then return span(sf, 1 / 3, 2 / 3) end
  if position == "lastThird" then return span(sf, 2 / 3, 1) end
  if position == "firstTwoThirds" then return span(sf, 0, 2 / 3) end
  if position == "centerTwoThirds" then return span(sf, 1 / 6, 5 / 6) end
  if position == "lastTwoThirds" then return span(sf, 1 / 3, 1) end
  return nil
end

-- The position whose base tile the frame sits in, if any
function M.positionOf(frame, sf)
  for position in pairs(M.POSITIONS) do
    if M.near(frame, M.baseTile(position, sf)) then return position end
  end
  return nil
end

-- What a press of `pressed` does. `last` is { key, position } when the window still
-- sits where this Spoon last put it. Returns the target position and a monitor step,
-- the step being nil when the window stays on its monitor.
function M.plan(pressed, last, currentPosition)
  if currentPosition == pressed or (last and last.position == pressed) then
    return pressed, M.POSITIONS[pressed].step
  end
  return pressed, nil
end

-- Monitors -------------------------------------------------------------------

function M.describeScreens(screens)
  local entries = {}
  for i, s in ipairs(screens) do
    entries[i] = { screen = s, id = s:id(), frame = M.rect(s:frame()) }
  end
  return entries
end

local function overlapArea(a, b)
  local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
  local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
  if w <= 0 or h <= 0 then return 0 end
  return w * h
end

-- Picked from frames already in hand rather than win:screen(), which costs another
-- Accessibility read. A window entirely off every screen falls back to the first.
function M.screenFor(frame, entries)
  local best, bestArea = entries[1], 0
  for _, e in ipairs(entries) do
    local area = overlapArea(frame, e.frame)
    if area > bestArea then best, bestArea = e, area end
  end
  return best
end

-- Two monitors share a row when their vertical spans overlap by at least half the
-- shorter one. A few points of overlap from a slightly misaligned arrangement stays
-- well under that, so it never merges rows.
local function sameRow(a, b)
  local overlap = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
  return overlap >= 0.5 * math.min(a.h, b.h)
end

-- Reading order: rows top to bottom, then left to right within a row, with monitors
-- stacked in one column taken top to bottom. Rows chain, so a tall portrait monitor
-- next to a stack of three puts all four in one row.
function M.order(entries)
  local n = #entries
  local parent = {}
  for i = 1, n do parent[i] = i end
  local function find(i)
    while parent[i] ~= i do i = parent[i] end
    return i
  end
  for i = 1, n do
    for j = i + 1, n do
      if sameRow(entries[i].frame, entries[j].frame) then parent[find(j)] = find(i) end
    end
  end

  local rows, rowOf = {}, {}
  for i = 1, n do
    local root = find(i)
    if not rowOf[root] then
      rowOf[root] = { members = {}, top = math.huge, left = math.huge }
      rows[#rows + 1] = rowOf[root]
    end
    local row, f = rowOf[root], entries[i].frame
    table.insert(row.members, entries[i])
    row.top = math.min(row.top, f.y)
    row.left = math.min(row.left, f.x)
  end
  table.sort(rows, function(a, b)
    if a.top ~= b.top then return a.top < b.top end
    return a.left < b.left
  end)

  local ordered = {}
  for _, row in ipairs(rows) do
    -- Left edges within SLACK form one column, assigned in a single pass so the
    -- sort below compares plain numbers
    local byX = {}
    for i, e in ipairs(row.members) do byX[i] = e end
    table.sort(byX, function(a, b) return a.frame.x < b.frame.x end)
    local column, columnStart, columnOf = 0, nil, {}
    for _, e in ipairs(byX) do
      if not columnStart or e.frame.x - columnStart > M.SLACK then
        column = column + 1
        columnStart = e.frame.x
      end
      columnOf[e] = column
    end
    table.sort(byX, function(a, b)
      if columnOf[a] ~= columnOf[b] then return columnOf[a] < columnOf[b] end
      return a.frame.y < b.frame.y
    end)
    for _, e in ipairs(byX) do ordered[#ordered + 1] = e end
  end
  return ordered
end

-- The monitor `step` places away from `here` in reading order, wrapping. Returns
-- `here` itself when it is the only monitor.
function M.nextScreen(entries, here, step)
  local ordered = M.order(entries)
  local index = 1
  for i, e in ipairs(ordered) do
    if e == here then index = i break end
  end
  return ordered[(index - 1 + step) % #ordered + 1]
end

return M
