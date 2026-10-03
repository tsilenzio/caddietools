-- Run: lua test/test_core.lua   (from the repo root)
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")
stub.install(".")
local Core = stub.loadSpoon("CaddieCore")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end

local function newSpoon(name)
  local s = Core.component({ name = name })
  s:action("act", { doc = "test action" })
  return s
end

-- Plain completion with no middleware
local s = newSpoon("Plain")
local r = s:run("act", {}, function() end)
check(r.status == "completed" and r.action == "act", "completes with no middleware")

-- Guard veto names its owner and reason, and the action does not run
s = newSpoon("Guarded")
local ran = false
s:use("act", function() return false, "nope" end, { kind = "guard", owner = "G", name = "block" })
r = s:run("act", {}, function() ran = true end)
check(r.status == "vetoed" and r.by == "G" and r.reason == "nope" and not ran, "guard vetoes with owner and reason")

-- Transform edits proposed before perform sees it
s = newSpoon("Transformed")
s:use("act", function(ctx) ctx.proposed.n = (ctx.proposed.n or 0) + 1 end, { kind = "transform", owner = "T" })
s:use("act", function(ctx) ctx.proposed.n = ctx.proposed.n * 10 end, { kind = "transform", owner = "T2" })
local seen
r = s:run("act", {}, function(ctx) seen = ctx.proposed.n end)
check(seen == 10, "transforms run in insertion order")

-- Observer sees the result and cannot veto
s = newSpoon("Observed")
local observed
s:use("act", function(ctx, result) observed = result.status end, { kind = "observer", owner = "O" })
r = s:run("act", {}, function() return { status = "unchanged" } end)
check(observed == "unchanged" and r.status == "unchanged", "observer sees result")

-- Error before next() skips the layer and the action still runs
s = newSpoon("BrokenBefore")
ran = false
s:use("act", function() error("boom") end, { kind = "transform", owner = "B" })
r, ctx = s:run("act", {}, function() ran = true end)
check(ran and r.status == "completed" and #ctx.errors == 1, "error before next skips the layer")

-- Error after next() keeps the outcome and does not rerun the action
s = newSpoon("BrokenAfter")
local runs = 0
s:use("act", function(ctx, result) error("late boom") end, { kind = "observer", owner = "A" })
r, ctx = s:run("act", {}, function() runs = runs + 1 end)
check(runs == 1 and r.status == "completed" and #ctx.errors == 1, "error after next keeps outcome, no rerun")

-- Calling next twice never runs the action twice
s = newSpoon("DoubleNext")
runs = 0
s:use("act", function(ctx, nextFn) nextFn() return nextFn() end, { owner = "D" })
s:run("act", {}, function() runs = runs + 1 end)
check(runs == 1, "double next runs action once")

-- Perform failure becomes a failed result
s = newSpoon("Failing")
r = s:run("act", {}, function() error("perform failed") end)
check(r.status == "failed" and r.error, "perform error gives failed result")

-- Events: exact and wildcard subscribers, payload built lazily, broken subscriber isolated
s = newSpoon("Events")
local exact, wild, built = nil, nil, 0
s:action("act", { snapshot = function(ctx, result) built = built + 1 return { status = result.status } end })
s:on("act.completed", function(p) exact = p.status end, "E")
s:on("act.completed", function() error("subscriber boom") end, "Bad")
s:on("*", function(p, name) wild = name end, "W")
s:run("act", {}, function() end)
check(exact == "completed" and wild == "act.completed" and built == 1, "events delivered once built, broken subscriber isolated")

s = newSpoon("NoListeners")
built = 0
s:action("act", { snapshot = function() built = built + 1 return {} end })
s:run("act", {}, function() end)
check(built == 0, "no payload built without listeners")

-- Removal handles
s = newSpoon("Removal")
local remove = s:use("act", function() return false end, { kind = "guard", owner = "R" })
remove()
r = s:run("act", {}, function() end)
check(r.status == "completed", "middleware removal handle works")

-- Memo caches nil
local calls = 0
s = newSpoon("Memo")
s:run("act", {}, function(ctx)
  ctx:get("k", function() calls = calls + 1 return nil end)
  ctx:get("k", function() calls = calls + 1 return nil end)
end)
check(calls == 1, "memo caches nil")

-- Scope releases in reverse order
local order = {}
local scope = Core.scope("T")
scope:add(function() table.insert(order, 1) end, "one")
scope:add(function() table.insert(order, 2) end, "two")
scope:close()
check(order[1] == 2 and order[2] == 1, "scope releases in reverse order")

-- Shutdown fan-out
local shut = 0
local sc = Core.scope("S")
sc:onShutdown(function() shut = shut + 1 end)
hs.shutdownCallback()
sc:close()
hs.shutdownCallback()
check(shut == 1, "shutdown handler runs and is removed on close")

-- prepare fills proposed before middleware, and can end the action early
s = newSpoon("Prepared")
local sawTarget
s:use("act", function(ctx) sawTarget = ctx.proposed.target end, { kind = "transform", owner = "P" })
s:run("act", {}, function() end, function(ctx) ctx.proposed.target = 42 end)
check(sawTarget == 42, "prepare runs before middleware")
ran = false
r = s:run("act", {}, function() ran = true end, function() return { status = "unchanged", reason = "no window" } end)
check(r.status == "unchanged" and not ran, "prepare can end the action early")

-- Unsubscribing everyone stops payload building
s = newSpoon("Unsub")
built = 0
s:action("act", { snapshot = function() built = built + 1 return {} end })
local off = s:on("*", function() end, "U")
off()
s:run("act", {}, function() end)
check(built == 0, "no payload built after the last subscriber leaves")

-- A middleware that runs the same action again before and after next() keeps both runs separate
s = newSpoon("Nested")
local depth, outerSaw, innerSaw = 0, nil, nil
s:use("act", function(ctx, nextFn)
  depth = depth + 1
  if depth == 1 then
    local inner = s:run("act", { tag = "inner" }, function(c) innerSaw = c.input.tag return { status = "completed", tag = "inner" } end)
    check(inner.tag == "inner", "nested run before next returns its own result")
  end
  local r = nextFn()
  if depth == 1 then
    local again = s:run("act", { tag = "inner2" }, function(c) return { status = "completed", tag = "inner2" } end)
    check(again.tag == "inner2", "nested run after next returns its own result")
  end
  return r
end, { owner = "N" })
r = s:run("act", { tag = "outer" }, function(c) outerSaw = c.input.tag return { status = "completed", tag = "outer" } end)
check(r.tag == "outer" and outerSaw == "outer" and innerSaw == "inner", "outer run keeps its own context through nested runs")

-- The screen watcher starts on first use, with no :start() call
local watchers, lists = {}, 0
hs.screen.watcher.new = function(fn)
  local w = { fn = fn }
  function w:start() self.running = true return self end
  function w:stop() self.running = false return self end
  table.insert(watchers, w)
  return w
end
hs.screen.allScreens = function() lists = lists + 1 return { "screen" } end
Core:stop()
Core.screens()
Core.screens()
check(#watchers == 1 and watchers[1].running and lists == 1, "the first screens() call starts one watcher and caches the list")
watchers[1].fn()
Core.screens()
check(lists == 2, "a screen change clears the cache")
Core:start()
check(#watchers == 1, "start after first use adds no second watcher")
Core:stop()
check(not watchers[1].running, "stop releases the watcher")

print(Core.inspect())
print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
