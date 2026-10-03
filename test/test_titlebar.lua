-- Run: lua test/test_titlebar.lua   (from the repo root)
-- Core.titlebar(): one shared click tap with ordered, swallowing subscribers, a
-- ref-counted drag tap, and the cached window lookup.
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")
stub.install(".")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end

local created = {}
hs.eventtap.new = function(evTypes, fn)
  local tap = { types = evTypes, fn = fn, running = false }
  function tap:start() self.running = true return self end
  function tap:stop() self.running = false return self end
  table.insert(created, tap)
  return tap
end
local function event(kind) return { getType = function() return kind end } end

local Core = stub.loadSpoon("CaddieCore")
local tb = Core.titlebar()
check(Core.titlebar() == tb, "Core.titlebar() returns one shared instance")
check(tb.clickTap == nil and #created == 0, "no tap until someone subscribes")

local seen = {}
local swallow = false
local offFirst = tb:subscribe("First", function(e) seen[#seen + 1] = "first" return swallow end)
local offSecond = tb:subscribe("Second", function(e) seen[#seen + 1] = "second" return false end)
check(#created == 1 and tb.clickTap.running, "two subscribers share one click tap")

check(tb.clickTap.fn(event("leftMouseDown")) == false and table.concat(seen, ",") == "first,second",
  "subscribers see events in the order they subscribed")
seen, swallow = {}, true
check(tb.clickTap.fn(event("leftMouseDown")) == true and table.concat(seen, ",") == "first",
  "a subscriber that swallows stops delivery to the rest")

offFirst()
check(tb.clickTap and tb.clickTap.running, "the tap stays while anyone is subscribed")
local tap = tb.clickTap
offSecond()
check(tb.clickTap == nil and not tap.running, "the last unsubscribe stops the tap")

-- The drag tap is held, not subscribed
local drags = 0
local releaseA = tb:drag("A", function() drags = drags + 1 end)
local releaseB = tb:drag("B", function() drags = drags + 10 end)
check(#created == 2 and tb.dragTap.running, "two holders share one drag tap")
check(tb.dragTap.fn(event("leftMouseDragged")) == false and drags == 11, "every holder sees each drag")
releaseA()
local dragTap = tb.dragTap
releaseB()
check(tb.dragTap == nil and not dragTap.running, "the drag tap stops once no one holds it")

-- Window lookup from the cached list, front to back
hs.window.list = function()
  return {
    { kCGWindowNumber = 1, kCGWindowOwnerPID = 10, kCGWindowLayer = 0, kCGWindowBounds = { X = 100, Y = 100, Width = 400, Height = 300 } },
    { kCGWindowNumber = 2, kCGWindowOwnerPID = 20, kCGWindowLayer = 25, kCGWindowBounds = { X = 0, Y = 0, Width = 2000, Height = 30 } },
    { kCGWindowNumber = 3, kCGWindowOwnerPID = 30, kCGWindowLayer = 0, kCGWindowBounds = { X = 0, Y = 0, Width = 1000, Height = 1000 } },
  }
end
check(tb:windowAt({ x = 150, y = 120 }) == nil, "nothing is found before the first refresh")
tb:refresh()
local e, dx, dy = tb:windowAt({ x = 150, y = 120 })
check(e and e.id == 1 and e.pid == 10 and dx == 50 and dy == 20, "the frontmost window wins, with the offset into it")
e = tb:windowAt({ x = 10, y = 10 })
check(e and e.id == 3, "windows off layer 0 are skipped")

print(Core.inspect())
print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
