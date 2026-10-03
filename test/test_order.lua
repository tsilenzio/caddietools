-- Run: lua test/test_order.lua   (from the repo root)
-- Monitor reading order and stepping in Core.geometry().
package.path = "./test/?.lua;" .. package.path
require("stub_hs").install(".")
local geometry = require("CaddieCore").geometry()

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end

local function entries(list)
  local out = {}
  for i, item in ipairs(list) do out[i] = { id = item[1], frame = item[2] } end
  return out
end

local function names(ordered)
  local out = {}
  for i, e in ipairs(ordered) do out[i] = e.id end
  return table.concat(out, " ")
end

local function walk(list, startId, step, count)
  local es = entries(list)
  local here
  for _, e in ipairs(es) do if e.id == startId then here = e end end
  local seen = { here.id }
  for _ = 1, count do
    here = geometry.nextScreen(es, here, step)
    seen[#seen + 1] = here.id
  end
  return table.concat(seen, " ")
end

-- The owner's layout: two ultrawides on top, laptop and a smaller monitor below
local DOCKED = {
  { "laptop", { x = 0, y = 40, w = 2056, h = 1250 } },
  { "uwRight", { x = 1028, y = -1410, w = 3440, h = 1410 } },
  { "other", { x = 2056, y = 30, w = 1920, h = 1200 } },
  { "uwLeft", { x = -2412, y = -1410, w = 3440, h = 1410 } },
}
check(names(geometry.order(entries(DOCKED))) == "uwLeft uwRight laptop other", "docked: reading order 1 2 3 4")
check(walk(DOCKED, "laptop", 1, 4) == "laptop other uwLeft uwRight laptop", "docked: right from the laptop stays in its row first")
check(walk(DOCKED, "uwLeft", -1, 4) == "uwLeft other laptop uwRight uwLeft", "docked: left walks the order backward")

-- The same layout with the left ultrawide a few points lower and the other monitor
-- poking a few points up into the ultrawide row
local NUDGED = {
  { "laptop", { x = 0, y = 40, w = 2056, h = 1250 } },
  { "uwRight", { x = 1028, y = -1410, w = 3440, h = 1410 } },
  { "other", { x = 2056, y = -3, w = 1920, h = 1200 } },
  { "uwLeft", { x = -2412, y = -1406, w = 3440, h = 1410 } },
}
check(names(geometry.order(entries(NUDGED))) == "uwLeft uwRight laptop other", "nudged: a few points of overlap does not merge rows")

-- The hypothetical layout: a tall portrait monitor beside a stack of three
local PORTRAIT = {
  { "laptop", { x = 1440, y = 1700, w = 2056, h = 900 } },
  { "other", { x = 1440, y = 800, w = 1920, h = 900 } },
  { "portrait", { x = 0, y = -100, w = 1440, h = 2700 } },
  { "uwRight", { x = 1440, y = -100, w = 3440, h = 900 } },
}
check(names(geometry.order(entries(PORTRAIT))) == "portrait uwRight other laptop", "portrait: one chained row, stack read top to bottom")
check(walk(PORTRAIT, "portrait", 1, 4) == "portrait uwRight other laptop portrait", "portrait: right cycles 1 2 3 4")

-- A single row: up and down cycle forward like right
local ROW = {
  { "b", { x = 2056, y = 0, w = 2056, h = 1250 } },
  { "a", { x = 0, y = 0, w = 2056, h = 1250 } },
}
check(walk(ROW, "a", 1, 2) == "a b a", "row: forward wraps")
local single = entries({ { "only", { x = 0, y = 0, w = 100, h = 100 } } })
check(geometry.nextScreen(single, single[1], 1) == single[1], "one monitor returns itself")

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
